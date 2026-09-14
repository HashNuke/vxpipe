// @ts-check
import { readFileSync } from 'node:fs';
import { defineConfig } from 'astro/config';

import starlight from '@astrojs/starlight';

// bin/dev --tailscale provisions the certificate before starting this process.
const tailscale = process.env.VXPIPE_DEV_TLS === 'phoenix';

// https://astro.build/config
export default defineConfig({
  server: tailscale ? {
    host: process.env.VXPIPE_TAILSCALE_IP,
    allowedHosts: [process.env.APP_HOST ?? ''],
  } : {},

  vite: {
    server: {
      https: tailscale ? {
        cert: readFileSync(process.env.VXPIPE_DEV_TLS_CERTFILE ?? ''),
        key: readFileSync(process.env.VXPIPE_DEV_TLS_KEYFILE ?? ''),
      } : undefined,
    },
  },

  redirects: {
    '/docs': '/docs/en/',
  },

  integrations: [starlight()],
});