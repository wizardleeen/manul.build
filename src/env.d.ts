/// <reference path="../.astro/types.d.ts"/>

interface ImportMetaEnv {
    readonly PUBLIC_MANUL_HOST: string
    readonly PUBLIC_MANUL_APP_ID: string
}

interface ImportMeta {
    readonly env: ImportMetaEnv
}