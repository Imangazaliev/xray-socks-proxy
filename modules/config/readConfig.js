import { promises as fs } from 'fs'
import path from 'path'

import { configSchema } from './schema.js'

export async function readConfig(rootDir) {
    const configPath = path.join(rootDir, 'config.json')
    const raw = await fs.readFile(configPath, 'utf8')
    const parsed = JSON.parse(raw)
    const result = configSchema.safeParse(parsed)

    if (! result.success) {
        const issues = result.error.issues.map(({ path: issuePath, message }) => {
            const pathLabel = issuePath.length > 0 ? issuePath.join('.') : 'config'

            return `${ pathLabel }: ${ message }`
        })

        throw new Error(`Invalid config.json:\n- ${ issues.join('\n- ') }`)
    }

    return result.data
}
