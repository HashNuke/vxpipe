# Vxpipe web samples

This package is the dogfooding and end-user example application for Vxpipe. It
contains a Vite/React TypeScript frontend, a Fastify TypeScript backend, and
Storybook for developing every project-owned UI state in isolation.

The Fastify backend will own sample orchestration and server-side credentials.
Browser media connects directly to Vxpipe using short-lived authorization from
the backend; the sample backend must not proxy the live audio path.

## Development

From this directory:

```shell
npm ci
npm run dev
```

Direct package development uses the frontend default of port 5173 and proxies
`/api` to the Fastify backend default of port 4100. Run component development
separately with:

```shell
npm run storybook -- --port 6006
```

From the repository root, `bin/setup` installs the locked dependencies and
assigns development ports. `bin/dev` starts the frontend, backend, Storybook,
and documentation processes using the worktree-local `.env.dev`.

## Checks

```shell
npm test
npm run lint
npm run typecheck
npm run build
npx --no-install storybook build
```

The initial catalog intentionally marks the WebSocket voice-room sample as
planned. It should become available only when it can exercise the real,
versioned Vxpipe room and media protocols.
