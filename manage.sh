#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_COMPOSE="${ROOT_DIR}/docker-compose.yml"
OUT_CONFIG="${ROOT_DIR}/out/xray-config.json"
GEN_COMPOSE="${ROOT_DIR}/out/docker-compose.yml"
OUT_CHECK="${ROOT_DIR}/out/check-proxy.sh"
NODE_SERVICE="node-tools"

log()  { echo "[info] $*"; }
ok()   { echo "[ok] $*"; }
warn() { echo "[warn] $*" >&2; }
err()  { echo "[error] $*" >&2; }

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Command not found: $cmd"
    exit 1
  fi
}

ensure_files() {
  [[ -f "${TOOLS_COMPOSE}" ]] || { err "Missing file: ${TOOLS_COMPOSE}"; exit 1; }
  [[ -f "${ROOT_DIR}/config.json" ]] || { err "Missing file: ${ROOT_DIR}/config.json"; exit 1; }
  [[ -f "${ROOT_DIR}/generator/generate.mjs" ]] || { err "Missing file: ${ROOT_DIR}/generator/generate.mjs"; exit 1; }
  [[ -f "${ROOT_DIR}/templates/xray-config.ejs" ]] || { err "Missing file: ${ROOT_DIR}/templates/xray-config.ejs"; exit 1; }
  [[ -f "${ROOT_DIR}/templates/docker-compose.ejs" ]] || { err "Missing file: ${ROOT_DIR}/templates/docker-compose.ejs"; exit 1; }
  [[ -f "${ROOT_DIR}/templates/check-proxy.sh.ejs" ]] || { err "Missing file: ${ROOT_DIR}/templates/check-proxy.sh.ejs"; exit 1; }
}

docker_compose() {
  docker compose "$@"
}

node_compose() {
  docker_compose -f "$TOOLS_COMPOSE" "$@"
}

node_exec() {
  if [[ $# -eq 0 ]]; then
    err "No command specified for ${NODE_SERVICE}."
    exit 1
  fi

  log "Running command in ephemeral ${NODE_SERVICE} container..."
  (cd "$ROOT_DIR" && node_compose run --rm "$NODE_SERVICE" "$@")
}

ensure_node_deps_installed() {
  if node_exec test -d ./node_modules/ejs; then
    return 0
  fi

  warn "Node.js dependencies are missing in the Docker volume. Installing them now..."
  node_exec npm ci
}

wait_for_healthy() {
  local service_name="$1"
  local container_id="$2"
  local attempts="${3:-30}"
  local sleep_seconds="${4:-2}"
  local attempt=1
  local status=""

  while (( attempt <= attempts )); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id" 2>/dev/null || true)"

    case "$status" in
      healthy)
        ok "Service ${service_name} is healthy."
        return 0
        ;;
      unhealthy)
        err "Service ${service_name} became unhealthy."
        return 1
        ;;
      running)
        err "Service ${service_name} is running but has no health status."
        return 1
        ;;
    esac

    log "Waiting for healthy status (${attempt}/${attempts})..."
    sleep "$sleep_seconds"
    (( attempt++ ))
  done

  err "Timed out waiting for service health. Last status: ${status:-unknown}"
  return 1
}

cmd_help() {
  cat <<'EOF'
Usage:
  ./manage.sh <command>

Commands:
  install-docker   Install Docker Engine + compose plugin (Ubuntu/Debian)
  install-deps     Install Node.js dependencies inside docker
  generate         Generate out/* from templates/*.ejs inside docker
  exec             Run a command inside the helper Node.js container
  check            Run proxy check from out/check-proxy.sh
  start            Generate config if needed, then start xray
  stop             Stop xray container
  restart          Stop, regenerate config, and start xray
  logs             Show docker compose logs

Examples:
  ./manage.sh install-deps
  ./manage.sh generate
  ./manage.sh exec npm run lint
  ./manage.sh check
  ./manage.sh start
  ./manage.sh restart
  ./manage.sh logs
EOF
}

cmd_install_docker() {
  if [[ $EUID -ne 0 ]]; then
    err "install-docker must be run as root (sudo)."
    exit 1
  fi

  log "Installing Docker Engine (Ubuntu/Debian)..."

  apt-get update -y
  apt-get install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local codename
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
  if [[ -z "$codename" ]]; then
    err "Cannot detect VERSION_CODENAME from /etc/os-release"
    exit 1
  fi

  local distro_id
  distro_id="$(. /etc/os-release && echo "${ID:-ubuntu}")"

  local repo_path="ubuntu"
  if [[ "$distro_id" == "debian" ]]; then
    repo_path="debian"
  fi

  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${repo_path} ${codename} stable
EOF

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  ok "Docker installed."
}

cmd_install_deps() {
  need_cmd docker
  ensure_files

  log "Installing Node.js dependencies in docker..."
  node_exec npm ci
  ok "Dependencies installed."
}

cmd_generate() {
  need_cmd docker
  ensure_files

  ensure_node_deps_installed

  log "Generating output files in docker..."
  node_exec node ./generator/generate.mjs
  ok "Generated ${OUT_CONFIG}, ${GEN_COMPOSE}, and ${OUT_CHECK}."
}

cmd_exec() {
  need_cmd docker
  ensure_files
  node_exec "$@"
}

cmd_check() {
  need_cmd curl
  [[ -f "$OUT_CHECK" ]] || {
    err "Generated check script not found: $OUT_CHECK"
    err "Run: ./manage.sh generate"
    exit 1
  }
  log "Running proxy check..."
  (cd "$ROOT_DIR" && "$OUT_CHECK")
}

cmd_start() {
  need_cmd docker
  ensure_files

  if [[ ! -f "$OUT_CONFIG" || ! -f "$GEN_COMPOSE" ]]; then
    warn "Generated files are missing in ${ROOT_DIR}/out"
    warn "Running generate first..."
    cmd_generate
  fi

  log "Starting xray..."
  (cd "$ROOT_DIR" && docker_compose -f "$GEN_COMPOSE" up -d)
  local container_id
  container_id="$(cd "$ROOT_DIR" && docker_compose -f "$GEN_COMPOSE" ps -q xray-proxy-client)"
  if [[ -z "$container_id" ]]; then
    err "Failed to resolve container id for service xray-proxy-client."
    exit 1
  fi
  wait_for_healthy xray-proxy-client "$container_id" 30 2
}

cmd_stop() {
  need_cmd docker

  if [[ -f "$GEN_COMPOSE" ]]; then
    log "Stopping xray..."
    (cd "$ROOT_DIR" && docker_compose -f "$GEN_COMPOSE" down --remove-orphans)
    ok "Service stopped."
  else
    warn "Generated compose not found: $GEN_COMPOSE"
  fi
}

cmd_restart() {
  cmd_stop
  cmd_generate
  cmd_start
}

cmd_logs() {
  need_cmd docker
  if [[ ! -f "$GEN_COMPOSE" ]]; then
    err "Generated compose not found: $GEN_COMPOSE"
    err "Run: ./manage.sh generate"
    exit 1
  fi
  log "Showing logs..."
  (cd "$ROOT_DIR" && docker_compose -f "$GEN_COMPOSE" logs)
}

main() {
  local cmd="${1:-}"

  case "$cmd" in
    ""|-h|--help|help) cmd_help ;;
    install-docker)   cmd_install_docker ;;
    install-deps)     cmd_install_deps ;;
    generate)         cmd_generate ;;
    exec)             shift; cmd_exec "$@" ;;
    check)            cmd_check ;;
    start)            cmd_start ;;
    stop)             cmd_stop ;;
    restart)          cmd_restart ;;
    logs)             cmd_logs ;;
    *)
      err "Unknown command: $cmd"
      echo
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
