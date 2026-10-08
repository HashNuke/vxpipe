import { readFileSync } from 'node:fs';

export function developmentServerConfig(env) {
  // bin/site-dev --tailscale provisions the certificate before starting Astro.
  const tailscale = env.VXPIPE_DEV_TLS === 'phoenix';

  return {
    server: {
      port: Number(env.ASTRO_PORT || 4321),
      ...(tailscale ? {
        host: env.VXPIPE_TAILSCALE_IP,
        allowedHosts: [env.APP_HOST ?? ''],
      } : {}),
    },

    vite: {
      server: {
        strictPort: true,
        https: tailscale ? {
          cert: readFileSync(env.VXPIPE_DEV_TLS_CERTFILE ?? ''),
          key: readFileSync(env.VXPIPE_DEV_TLS_KEYFILE ?? ''),
        } : undefined,
      },
    },
  };
}
