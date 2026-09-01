# Vxpipe

Vxpipe is an umbrella project for reusable, Membrane-backed voice call rooms
and a standalone HTTP/WebSocket service.

## Applications

- `vxpipe` contains the provider-neutral call-room runtime, shared supervision,
  and Membrane media graph.
- `vxpipe_web` contains reusable Plug and WebSock integration. It does not open
  a network port and can be mounted by another Plug or Phoenix application.
- `vxpipe_server` starts Bandit and is the entry point for the standalone OTP
  release and Docker image.
- `samples` contains the Vite/React sample frontend, Fastify TypeScript
  backend, and Storybook component workshop used for dogfooding and end-user
  examples.

Provider integrations such as Telnyx, Deepgram, and Rime belong in separate
adapter applications that depend on `vxpipe`. The core application must not
depend on provider adapters.

## Development

Set up a fresh checkout or worktree:

```shell
bin/setup
```

This installs Goreman into `$HOME/bin` when it is not already on `PATH`, writes
the worktree-local `.env.dev` used only by Goreman and its children, fetches the
Elixir dependencies, and installs the locked Starlight and samples dependencies.
Run setup again after adding or removing a `Procfile.dev` process.

The primary checkout uses the stable ports declared in `.env.dev.defaults`:
docs on `4321`, the samples backend on `4100`, Vite on `5173`, and Storybook on
`6006`. A linked Git worktree receives an unused contiguous block with one port
per Procfile process. Setup excludes the primary defaults, listening ports, and
blocks already recorded by other worktrees.
Variables in `.env.dev` whose names do not start with `DEV_PORT_` are preserved
when setup refreshes the allocation, so the file can also hold local values
that should be visible only to Goreman-managed development processes.

Run the umbrella test suite with:

```shell
mix test
```

Start the standalone server on `127.0.0.1:4000`:

```shell
mix run --no-halt
```

Build the self-contained release:

```shell
MIX_ENV=prod mix release vxpipe
```

The release listens on `0.0.0.0` and reads its port from `PORT`, defaulting to
`4000`.

## Documentation

The documentation site is a self-contained Starlight project, with Astro as its
underlying build system. Set up the project and start the development processes
from the umbrella root:

```shell
bin/setup
bin/dev
```

`bin/dev` loads `.env.dev` into Goreman and the processes it manages, then
starts the live-reloading documentation site, the sample Fastify backend, the
Vite sample frontend, and Storybook. It checks that every configured port is
available before starting. Inspect `.env.dev` for a worktree's assigned ports.

Build the static site with:

```shell
npm --prefix docs run build
```

The samples package has its own checks and production builds:

```shell
npm --prefix samples test
npm --prefix samples run lint
npm --prefix samples run build
npm --prefix samples exec -- storybook build
node --test test/dev_ports_test.mjs
```
