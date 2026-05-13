import { z } from 'zod'

const normalizedStringSchema = z.string().transform((value) => value.trim())
const normalizedNonEmptyStringSchema = normalizedStringSchema.pipe(z.string().min(1))

const authSchema = z.object({
    password: normalizedStringSchema,
    username: normalizedStringSchema,
}).refine(({ username, password }) => {
    const hasUsername = username.length > 0
    const hasPassword = password.length > 0

    return hasUsername === hasPassword
}, {
    message: 'username and password must either both be set or both be empty',
    path: ['username'],
})

export const configSchema = z.object({
    auth: authSchema.default({
        password: '',
        username: '',
    }),
    proxy: z.object({
        listen: normalizedNonEmptyStringSchema.default('0.0.0.0'),
        port: z.number().int().positive().max(65535).default(8444),
    }).default({
        listen: '0.0.0.0',
        port: 8444,
    }),
})
