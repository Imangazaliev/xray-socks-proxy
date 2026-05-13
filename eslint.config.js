import simpleImportSort from 'eslint-plugin-simple-import-sort'
import globals from 'globals'

export default [
    {
        ignores: [
            'node_modules/**',
            'out/**',
        ],
    },
    {
        languageOptions: {
            globals: {
                ...globals.node,
            },
        },
        plugins: {
            'simple-import-sort': simpleImportSort,
        },
        files: [
            '**/*.{js,cjs,mjs}',
        ],
        rules: {
            'comma-dangle': [
                'error',
                'always-multiline',
            ],
            indent: ['error', 4, {
                SwitchCase: 1,
            }],
            'simple-import-sort/imports': [
                'error',
                {
                    groups: [
                        ['^\\w', '^@\\w'],
                        ['^\\u0000'],
                        ['^~/'],
                        ['^\\.\\.'],
                        ['^\\.'],
                    ],
                },
            ],
            'linebreak-style': [
                'error',
                'unix',
            ],
            'newline-before-return': 'error',
            'no-duplicate-imports': 'error',
            'no-multiple-empty-lines': 'error',
            'no-restricted-imports': ['error', {
                patterns: [{
                    regex: '[a-zA-Z]+/internal/',
                    message: 'Usage of internal API are forbidden',
                }],
            }],
            'no-trailing-spaces': 'error',
            'no-undef': 'error',
            'no-unused-vars': 'error',
            'object-curly-spacing': ['error', 'always'],
            quotes: [
                'error',
                'single',
            ],
            semi: [
                'error',
                'never',
            ],
            'space-unary-ops': [
                'error',
                {
                    words: true,
                    nonwords: true,
                },
            ],
            'template-curly-spacing': [
                'error',
                'always',
            ],
        },
    },
]
