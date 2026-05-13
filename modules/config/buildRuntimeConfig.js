export function buildRuntimeConfig(config) {
    return {
        ...config,
        usePasswordAuth: config.auth.username.length > 0 && config.auth.password.length > 0,
    }
}
