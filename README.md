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

Provider integrations such as Telnyx, Deepgram, and Rime belong in separate
adapter applications that depend on `vxpipe`. The core application must not
depend on provider adapters.

## Development

Fetch dependencies and run the umbrella test suite:

```shell
mix deps.get
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
underlying build system. Install its dependencies, install
[Forego](https://github.com/ddollar/forego), and start the development processes
from the umbrella root:

```shell
npm --prefix docs install
bin/dev
```

`bin/dev` runs `Procfile.dev`. It currently starts the live-reloading
documentation server; more development processes can be added there over time.

Build the static site with:

```shell
npm --prefix docs run build
```
