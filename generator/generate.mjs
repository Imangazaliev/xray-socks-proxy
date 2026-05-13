import ejs from 'ejs'
import fs from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { buildRuntimeConfig, readConfig } from '../modules/config/index.js'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const rootDir = path.resolve(__dirname, '..')
const xrayTemplatePath = path.join(rootDir, 'templates', 'xray-config.ejs')
const composeTemplatePath = path.join(rootDir, 'templates', 'docker-compose.ejs')
const checkTemplatePath = path.join(rootDir, 'templates', 'check-proxy.sh.ejs')
const outDir = path.join(rootDir, 'out')
const outConfigPath = path.join(outDir, 'xray-config.json')
const outComposePath = path.join(outDir, 'docker-compose.yml')
const outCheckPath = path.join(outDir, 'check-proxy.sh')
const legacyOutCheckPath = path.join(outDir, 'check-proxy.mjs')

async function main() {
    const config = await readConfig(rootDir)
    const runtimeConfig = buildRuntimeConfig(config)

    await fs.mkdir(outDir, { recursive: true })

    const rendered = await ejs.renderFile(xrayTemplatePath, runtimeConfig, {
        async: true,
    })
    const renderedCompose = await ejs.renderFile(composeTemplatePath, runtimeConfig, {
        async: true,
    })
    const renderedCheck = await ejs.renderFile(checkTemplatePath, runtimeConfig, {
        async: true,
    })

    await fs.writeFile(outConfigPath, `${ rendered.trim() }\n`)
    await fs.writeFile(outComposePath, `${ renderedCompose.trim() }\n`)
    await fs.writeFile(outCheckPath, `${ renderedCheck.trim() }\n`)
    await fs.chmod(outCheckPath, 0o755)
    await fs.rm(legacyOutCheckPath, { force: true })

    console.log(`Generated ${ path.relative(rootDir, outConfigPath) }`)
    console.log(`Generated ${ path.relative(rootDir, outComposePath) }`)
    console.log(`Generated ${ path.relative(rootDir, outCheckPath) }`)
}

main().catch((error) => {
    console.error(error.message)
    process.exit(1)
})
