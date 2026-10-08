import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

function loadConfig(env) {
  const result = spawnSync(process.execPath, ['--input-type=module', '--eval', `
    import { developmentServerConfig } from './src/config/development-server.mjs';
    const config = developmentServerConfig(process.env);
    console.log(JSON.stringify({
      host: config.server?.host ?? false,
      allowedHosts: config.server?.allowedHosts ?? [],
      port: config.server?.port ?? 4321,
      strictPort: config.vite?.server?.strictPort ?? false,
      https: config.vite?.server?.https ? {
        cert: config.vite.server.https.cert.toString(),
        key: config.vite.server.https.key.toString(),
      } : null,
    }));
  `], {
    cwd: new URL('..', import.meta.url),
    env: { ...process.env, ...env },
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

test('ordinary development keeps localhost HTTP despite stale Tailscale settings', () => {
  for (const mode of ['', 'http']) {
    assert.deepEqual(loadConfig({
      VXPIPE_DEV_TLS: mode,
      VXPIPE_TAILSCALE_IP: '100.64.0.12',
      APP_HOST: 'console.example.ts.net',
      VXPIPE_DEV_TLS_CERTFILE: '/missing/cert.crt',
      VXPIPE_DEV_TLS_KEYFILE: '/missing/cert.key',
    }), { host: false, allowedHosts: [], port: 4321, strictPort: true, https: null });
  }
});

test('Tailscale development uses the launcher address and certificate on port 4321', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'vxpipe-astro-config-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const certFile = join(directory, 'tailscale.crt');
  const keyFile = join(directory, 'tailscale.key');
  writeFileSync(certFile, 'fixture certificate');
  writeFileSync(keyFile, 'fixture key');

  assert.deepEqual(loadConfig({
    VXPIPE_DEV_TLS: 'phoenix',
    VXPIPE_TAILSCALE_IP: '100.64.0.12',
    APP_HOST: 'console.example.ts.net',
    VXPIPE_DEV_TLS_CERTFILE: certFile,
    VXPIPE_DEV_TLS_KEYFILE: keyFile,
  }), {
    host: '100.64.0.12',
    allowedHosts: ['console.example.ts.net'],
    port: 4321, strictPort: true,
    https: { cert: 'fixture certificate', key: 'fixture key' },
  });
});


test('assigned Astro port is used without automatic port drift', () => {
  const config = loadConfig({ ASTRO_PORT: '14321', VXPIPE_DEV_TLS: 'http' });
  assert.equal(config.port, 14321);
  assert.equal(config.strictPort, true);
});
