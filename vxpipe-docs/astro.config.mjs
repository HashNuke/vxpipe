// @ts-check
import { defineConfig } from 'astro/config';

import react from '@astrojs/react';
import starlight from '@astrojs/starlight';
import starlightThemeBlack from 'starlight-theme-black';
import { developmentServerConfig } from './src/config/development-server.mjs';

const developmentServer = developmentServerConfig(process.env);

// https://astro.build/config
export default defineConfig({
  ...developmentServer,

  vite: {
    ...developmentServer.vite,
    // Resolve LobeHub's extensionless imports when rendering icons in Node.
    environments: {
      ssr: { resolve: { noExternal: ['@lobehub/icons'] } },
      prerender: { resolve: { noExternal: ['@lobehub/icons'] } },
    },
  },

  redirects: {
    '/en': '/',
    '/docs': '/en/docs/',
    '/docs/en': '/en/docs/',
  },

  integrations: [
    react(),
    starlight({
      title: 'VxPipe',
      defaultLocale: 'en',
      locales: {
        en: { label: 'English' },
      },
      plugins: [
        starlightThemeBlack({
          navLinks: [
            { label: 'Home', link: '/' },
            { label: 'Docs', link: '/docs/' },
          ],
        }),
      ],
      sidebar: [
        {
          label: 'Documentation',
          items: [{ autogenerate: { directory: 'docs' } }],
        },
      ],
    }),
  ],
});
