// @ts-check
import { defineConfig } from 'astro/config';

import tailwindcss from '@tailwindcss/vite';

import icon from 'astro-icon';

import expressiveCode from 'astro-expressive-code';
import fs from 'node:fs';

const manulGrammar = JSON.parse(fs.readFileSync('./manul.tmLanguage.json', 'utf-8'));

// https://astro.build/config
export default defineConfig({
  vite: {
    plugins: [tailwindcss()]
  },

  i18n: {
    locales: ['en', 'zh'],
    defaultLocale: 'en',
    routing: {
      prefixDefaultLocale: false
    }
  },

  integrations: [icon(), expressiveCode({
    themes: ['github-dark'], 
    shiki: {
      langs: [manulGrammar]
    }
  })],
});