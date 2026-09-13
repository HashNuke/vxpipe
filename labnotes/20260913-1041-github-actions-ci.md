# GitHub Actions CI

## Scope and decisions

- Add CI on the newest available GitHub-hosted Ubuntu runner, as requested.
  The worktree was clean before this checkpoint. No existing workflows or local
  runtime version file were present.
- GitHub's [runner image list](https://github.com/actions/runner-images) and
  [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
  list Ubuntu 26.04 in public preview on 2026-09-13; `ubuntu-latest` still points to
  24.04. Select `ubuntu-26.04` explicitly to satisfy the newest-image request.
- Match the available local Elixir 1.19.5 / OTP 28.5 toolchain and Node.js 24.
  [setup-beam](https://github.com/erlef/setup-beam) documents Ubuntu 26.04 support,
  and the Hex build index contains OTP 28.5 for that image. Its default setup
  installs Hex and Rebar. GitHub's image supplies Rust; explicitly install the
  C/C++ tools, pkg-config, and OpenSSL development headers needed by native deps.
- Use a disposable PostgreSQL 18 service with health checks and the existing
  `VXPIPE_TEST_DATABASE_URL` contract. Trust authentication is confined to test
  data in the ephemeral CI service. The umbrella test alias creates/migrates the
  database; no application configuration changes are needed.
- One job runs the five umbrella completion checks plus the existing Console
  setup, build/type-check, and test aliases. Use `MIX_ENV=test` throughout to avoid
  development credentials. External integration tests retain their default
  exclusions. Cache dependency sources and npm downloads; compile the umbrella
  afresh on each run so the compiler gate sees all project modules.
- Enable push, pull-request, and manual triggers, read-only repository permission,
  a 30-minute timeout, and cancellation of superseded runs for the same event/ref.
- Configuration and documentation only: the AGENTS.md exception permits skipping
  an initial red behavior test. No milestone implementation state changes.

## Verification

- actionlint 1.7.12 initially reported only an unknown `ubuntu-26.04` runner label:
  its bundled runner catalog lags GitHub's published image list. Re-ran with only
  that specific diagnostic filtered (`-ignore 'label "ubuntu-26\.04" is unknown'`);
  workflow syntax, expressions, action inputs, and embedded shell checks passed.
  The runner label was separately verified against GitHub's official references.
  No repository lint suppression or self-hosted runner declaration was added.
- All nine workflow commands passed locally on macOS with `MIX_ENV=test`,
  Elixir 1.19.5 / OTP 28.5, Node.js 24.18.0, and PostgreSQL 18.4:
  - `mix deps.get --check-locked` and `mix deps.unlock --check-unused` passed;
    neither lockfile changed.
  - `mix format --check-formatted`, `mix compile --warnings-as-errors`, and
    `mix credo --strict` passed. Credo checked 803 source files with no issues.
  - `mix assets.setup`, `mix assets.build`, and `mix assets.test` passed;
    TypeScript/esbuild succeeded and all 10 frontend tests in five files passed.
  - `mix test` reported 996 tests across eight applications, zero failures,
    and 15 excluded integration tests. The existing local PostgreSQL service
    supplied the database; the GitHub service container was not run locally.
- `git diff --check`, npm lockfile parsing, and verification
  that the referenced GitHub action major-version tags exist all passed.
- Final scope is the workflow and this labnote. The user removed the README CI
  note before requesting the commit; that removal is preserved. No
  application code, dependencies, lockfiles, or milestone statuses changed.
- Actual hosted-runner execution requires pushing this workflow to GitHub; no
  hosted result is claimed by local validation.
