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

## Run a production release

After preparing the checkout, build the assets and named umbrella release:

```shell
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release vxpipe
```

`assets.deploy` also generates Phoenix's asset manifest and fingerprinted files.
Build it before assembling the release so OAuth pages load the matching assets
after deployment, even when a browser has cached an earlier bundle.

Supply the [runtime configuration](../usage/configuration.md) through your service
manager or container environment. The release does not load `.env` automatically.
Create the PostgreSQL database first, then apply its migrations before starting:

```shell
_build/prod/rel/vxpipe/bin/migrate
_build/prod/rel/vxpipe/bin/vxpipe start
```

`bin/migrate` uses the Phoenix-generated release helper in `vxpipe_persistence`.
It applies the migrations bundled from
[`priv/repo/migrations`](../../../apps/vxpipe_persistence/priv/repo/migrations),
without starting the Console or background jobs. Completed versions are recorded
in PostgreSQL's `schema_migrations` table; subsequent runs apply pending versions.
A migration failure returns a nonzero exit status.

These commands run the packaged release without Mix. Put an HTTPS reverse proxy
in front of its internal `PORT`, set `APP_HOST` to the public hostname without a
scheme, and configure the proxy to redirect HTTP to HTTPS. Development asset
watchers and Storybook are not part of this release.

## Local fixtures

The local Morse provider exercises audio without external credentials:

```shell
cd apps/vxpipe_call_engine
mix test test/vxpipe/call_engine/provider/morse_code/room_round_trip_test.exs
```

The browser sample uses its configured providers; it does not silently switch to
fixtures. Use the provider-backed playground below for a voice call.

Silero VAD uses Ortex. On macOS the project disables Cargo release stripping for
that dependency to avoid malformed native-library string tables. If a checkout
has an older broken artifact, rebuild Ortex in development/test and run the real
inference checks:

```shell
mix deps.compile ortex --force
MIX_ENV=test mix deps.compile ortex --force
mix test apps/vxpipe_call_engine/test/vxpipe/call_engine/speech/silero_test.exs
```

## Provider-backed playground

Configure provider integrations through Console, then create or import a call spec
from `examples/call-specs/`. Select the saved credential names in that spec and
publish it for the intended tenant. Provider/model choices and credentials are
stored in the database; development and production need no application-level
speech-provider enablement.

The retired `VXPIPE_DEV_TENANT` shortcut no longer installs a hard-coded development
call. Use the saved call spec's test/playground flow. Verify a spoken exchange and
its transcript: text alone does not prove microphone input or audible playback.
Stop the call when finished.

For a credential-free development check, use the local Morse fixture lane in
[Local fixtures](#local-fixtures).

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
after merge.

From the sibling website checkout, preview canonical edits with:

```shell
npm ci
npm run docs:import -- ../vxpipe/docs
npm run build
npm run preview
```

The importer preserves the landing page, converts handbook links to site routes,
copies shared assets and pins source-code links to the source Git revision. Commit
the canonical changes before publishing so those source links resolve. The
generated `src/content/docs-source.json` records that revision.

## Publish and recover documentation

The `Publish documentation` GitHub workflow imports and builds a documentation
push from the selected branch, then commits the generated files to
`HashNuke/vxpipe-web` on `main`. Its existing Cloudflare Workers Builds integration
deploys that website commit. The workflow uses a write-enabled deploy key scoped
to the website repository, stored as `DOCS_WEBSITE_DEPLOY_KEY` in the canonical
repository's Actions secrets. Rotate the matching website deploy key and source
secret together.

After merging this documentation work, switch the publishing source:

```shell
gh variable set DOCS_PUBLISH_BRANCH --repo HashNuke/vxpipe --body main
```

This setting does not merge branches. Push a documentation change on `main` to
publish from it; once the workflow is on the default branch, it can also be run
manually through GitHub Actions.

For a failed publication, inspect the `Publish documentation` run in the source
repository. An import/build failure leaves the website branch unchanged. Fix
broken links, frontmatter or build errors in their owning repository, then push
the correction or rerun the failed run with `gh run rerun RUN_ID --failed --repo
HashNuke/vxpipe`. A concurrent website push can reject the publisher's push; rerun
to import onto the latest website revision. Never force-push generated content.

After publication succeeds, check the website commit's Cloudflare build separately.
A successful import is not proof of a successful hosted deployment. Confirm the
changed page on the public site and compare the recorded source revision.
