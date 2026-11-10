---
title: Development workflow
description: Prepare a checkout, run the Console and contribute to the canonical handbook.
sidebar:
  order: 1
---

## Prepare a checkout

Use the versions in [`.tool-versions`](../../../.tool-versions): Erlang/OTP 28,
Elixir 1.19, Node.js and Python. Also install PostgreSQL, Rust, C/C++ build tools,
`pkg-config` and OpenSSL development headers. Start PostgreSQL before setup.

```shell
git clone https://github.com/HashNuke/vxpipe.git
cd vxpipe
bin/setup
bin/dev
```

Run setup in each checkout/worktree. It fetches dependencies, applies the reviewed
ExMCP patch, builds assets, creates local secrets and migrates isolated development
and test databases. Rerunning preserves existing local configuration and data.
Use `bin/setup --with-lean` when working on the formal verification lane.

Setup prints Console and Storybook URLs. `bin/dev` loads the checkout's `.env` and
starts the umbrella with frontend rebuilds. Restart after backend/runtime config
changes. Direct Mix commands use worktree database defaults but do not load `.env`.

## Isolation and HTTPS

Ignored `.vxpipe/worktree.json` records checkout identity, databases and ports.
Switching branches within a checkout retains that identity. Database ownership
checks prevent one worktree from taking over another's data. Explicit database,
`PORT` and `STORYBOOK_PORT` overrides take precedence over assigned defaults.

To assign new ports, stop the checkout's servers and run:

```shell
bin/setup --reassign-ports
```

For HTTPS on a configured Tailscale machine with `jq` installed:

```shell
bin/dev --tailscale
```

This uses the machine's Tailscale address and certificates. Public carrier
callbacks require the separate ingress arrangement described under
[Testing and verification](testing.md#live-telephony).

## Local fixtures

The local Morse provider exercises audio without external credentials:

```shell
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/provider/morse_code/room_round_trip_test.exs
```

The browser sample uses its configured providers; it does not silently switch to
fixtures. See [Getting started](../usage/getting-started.md) for a provider-backed call.

Silero VAD uses Ortex. On macOS the project disables Cargo release stripping for
that dependency to avoid malformed native-library string tables. If a checkout
has an older broken artifact, rebuild Ortex in development/test and run the real
inference checks:

```shell
mix deps.compile ortex --force
MIX_ENV=test mix deps.compile ortex --force
mix test apps/vxpipe_call_engine/test/vxpipe/call_engine/speech/silero_test.exs
```

## Repository map

`apps/` contains the Elixir applications; `packages/` contains reusable browser
clients; `integrations/` is the public integration directory source. Supporting
checkouts sit alongside this one: `../vxpipe-integrations-web` publishes that
directory, and `../vxpipe-docs` is the website checkout of `HashNuke/vxpipe-web`.

Keep code, focused checks and documentation together in coherent commits. Read
[`AGENTS.md`](../../../AGENTS.md) for repository rules. Implementation milestones
and dated evidence live under `labnotes/`, outside the handbook. See
[Testing and verification](testing.md) for required checks.

## Write documentation

This repository owns the handbook. Use `docs/en/usage` for operator workflows and
`docs/en/development` for architecture and implementation contracts. Architecture
does not need a separate top-level tree. Keep decisions and their reasons with
the chapter that owns the behavior; keep historical test counts in labnotes.

Each page starts with Starlight frontmatter:

```yaml
---
title: A clear page title
description: One sentence explaining what the reader will learn.
sidebar:
  order: 1
---
```

Use relative Markdown links with `.md` extensions and stable headings. Link source
files relative to the document; the website importer converts those to GitHub
links. Put downloadable shared files in `docs/assets/`. Mermaid fences are for
small ownership/flow diagrams; include a prose explanation as well.

English uses `en`, matching
[Starlight's locale convention](https://starlight.astro.build/guides/i18n/).
A regional `en-US` adds no benefit for this handbook. Add future languages to
`docs/locales.json` and mirror the English page paths under their locale directory.
Keep code identifiers and URLs unchanged when translating.

The website imports canonical content into `src/content/docs/<lang>/docs/`.
Do not edit those generated copies. Publication is selected by the application
repository's `DOCS_PUBLISH_BRANCH` variable: `docs` during this work, then `main`
after merge. The publication implementation and its end-to-end verification are
tracked in the [handbook milestone](../../../labnotes/milestones/consolidated-handbook-and-publication.md).
