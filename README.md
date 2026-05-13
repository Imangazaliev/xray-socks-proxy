# xray-socks-proxy

Минимальная обвязка для запуска SOCKS5-прокси на базе Xray через шаблоны `ejs`.

## Setup

1. Создать локальный конфиг:

```bash
cp config.example.json config.json
```

2. Установить зависимости через одноразовый Node.js-контейнер:

```bash
./manage.sh install-deps
```

Node.js на хосте не нужен: `manage.sh` запускает одноразовый сервис `node-tools` из корневого `docker-compose.yml`, а `node_modules` кешируются в Docker volume.

3. Сгенерировать файлы в `out/`:

```bash
./manage.sh generate
```

Если Docker volume `node_modules` ещё пустой, `generate` автоматически выполнит `npm ci` внутри `node-tools` и затем продолжит генерацию.

При необходимости можно выполнить произвольную команду внутри этого контейнера:

```bash
./manage.sh exec npm run lint
```

## Run

Запуск:

```bash
./manage.sh start
```

`start` ждёт `healthy`-статус контейнера: healthcheck внутри Docker проверяет, что Xray реально слушает настроенный TCP-порт, а не просто что контейнер запущен.

Остановка:

```bash
./manage.sh stop
```

Перезапуск:

```bash
./manage.sh restart
```

Логи:

```bash
./manage.sh logs
```

## Check

Проверка прокси:

```bash
./manage.sh check
```

`check` не запускает `generate` автоматически. Если `out/check-proxy.sh` ещё не создан или конфиг менялся, сначала выполните:

```bash
./manage.sh generate
```

## Config

`config.json`:

```json
{
  "proxy": {
    "listen": "0.0.0.0",
    "port": 8444
  },
  "auth": {
    "username": "",
    "password": ""
  }
}
```

Если `auth.username` и `auth.password` пустые, прокси работает без авторизации. Если задать одно поле, нужно задать и второе.
