---
title: Testing and verification
description: Focused tests, browser checks, live providers, MCP conformance and Lean models.
sidebar:
  order: 9
---

Test project-owned behavior at the application that owns it. For runtime changes,
write the smallest externally observable failing case, implement the change,
then refactor while it remains green. Do not test guarantees already supplied by
Elixir, OTP or a dependency. Documentation/mechanical changes use proportionate
content, link and build checks.

## Local checks

Run focused tests from the owning child while iterating. For code/dependency
changes, finish from the umbrella root with:

```shell
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix deps.unlock --check-unused
```

For Console assets, use the existing `mix assets.build` and `mix assets.test`
tasks. Browser workspaces have `npm test`, `npm run check` and
`npm run build-storybook` at the root. Run `mix help TASK` before unfamiliar Mix
tasks/options. Setup and each child test helper define isolated database defaults
and the excluded integration/live lanes.

Use `start_supervised!`, monitors, acknowledgements and explicit failure barriers
to synchronize process tests. Avoid sleeps and liveness polling. Verify exact
ownership, stale completion rejection and resource drainage at the boundary;
do not inspect another application's private state as its public contract.

## Browser and native media

Every UI change needs rendered inspection. Run `agent-browser` with Chrome for
layout, CSS, responsive behavior, accessibility or media APIs. Check desktop and
mobile, important failure/empty/loading states, direct URLs and browser history.
Storybook supports bounded state review; it cannot prove real OAuth, microphone
capture, provider calls or persistence.

Native WebRTC tests use actual local ExWebRTC peers without a browser:

```shell
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs
```

These exercise signaling, decoded audio, private briefing, readiness/cue ordering,
failure recovery and participant teardown. They complement browser interoperability
and live carrier checks. Keep public-network fixtures tagged `integration` and
excluded from the ordinary suite.

## Live providers

Use [`bin/livetests`](../../../bin/livetests), which loads the protected operator
credential file only into its child test process. Do not read, print or modify
that file during routine development. The operator manages credentials from the
checked-in [example](../../../config/live_providers.env.example).

Select only the required provider/app:

```shell
bin/livetests run --only live_deepgram apps/vxpipe_gateway/test/integration
bin/livetests run --only live_elevenlabs \
  apps/vxpipe_console/test/integration/elevenlabs_configured_room_test.exs
```

With no selection, the runner runs all live provider tests. Live modules carry `live_providers`
and provider tags; they do not use the ordinary integration tag. A broad
`--include integration` must not unexpectedly contact paid providers.

Distinguish three kinds of evidence:

| Lane | What it proves |
| --- | --- |
| Local contract | Synthetic encrypted records, scoped selection, current authority and deterministic protocol/lifecycle decisions. |
| Live protocol | A real provider accepts the adapter's requests and returns expected evidence. |
| Live configured service | A call spec reaches the real provider through normal saved credential/service resolution. |

A direct protocol test with an injected key does not prove tenant resolution.
Generated speech samples may be cached for reuse; review them before committing.

## Live telephony

The harness calls machine-owned test numbers between Vxpipe rooms, not people.
Telnyx carries tests unrelated to Twilio; Twilio-specific lanes require its own
configuration. Public callbacks and WSS are required independently of local
Console/Tailscale access.

```shell
bin/livetests tools:status
bin/livetests telephony:status
bin/livetests run --only live_telnyx
```

`run` starts/stops only tools it owns and does not provision carrier resources.
`telephony:provision` discovers/creates machine resources; number purchase requires
its explicit `--allow-purchase` flag and separate authorization for that expense.

Live work reserves the named Git branch across checkouts. Before switching away,
finish live activity and run `bin/livetests release`. A failed test retains the
reservation. Read-only status commands remain available to other branches.

After an interrupted run, `bin/livetests telephony:hangup` ends calls associated
with this machine's provisioned test numbers. Carrier-specific variants are
`telnyx:hangup` and `twilio:hangup`. The optional `--all-calls` expands to unrelated
account calls too; it is not routine test cleanup. Test teardown also retains
and verifies the exact carrier handles it allocated.

Check both dial directions, ringing timeout, reciprocal audio, private acceptance,
selective destination hangup and natural archive closure. Controlled decoded media
does not establish what a person heard on a phone.

## MCP protocols

Outbound protocol lanes use the pinned `2025-11-25` profile and committed dependency
revision/patch:

```shell
bin/test-mcp-conformance
bin/test-mcp-sse-recovery
bin/test-mcp-everything
bin/test-shared-tools
```

The first script runs the official initialize and tools-call scenarios. The SSE
recovery runner applies a recorded fixture protocol-version correction; report it
as a corrected-fixture result, not an unmodified official pass. Everything checks
a pinned reference server and selected tools. None alone proves every OAuth,
tenant-runtime or provider capability.

For inbound platform MCP, cache the runner's exact tools, then run its acceptance:

```shell
npm exec --yes \
  --package=@modelcontextprotocol/conformance@0.1.16 \
  --package=@modelcontextprotocol/sdk@1.30.0 \
  -- node --version
bin/test-platform-mcp
```

This uses isolated loopback Gateway, mounted Gateway and Console endpoints with
real synthetic persisted OAuth authority. Run serially with database tests because
the fixture owns a shared SQL sandbox transaction. It exercises protocol tools,
permission filtering, revocation and prepared-call operations, not real media.

Saved-MCP acceptance additionally covers static/OAuth browser workflows, catalog
pinning, current request credentials, independent-node renewal, admitted calls,
transfer and teardown. Use the relevant existing Console/Persistence/Engine
integration tests; record exactly which boundary passed.

## Formal verification

For changes to a source-cutover or speech state machine, run:

```shell
bin/verify-lean
```

The standalone [`verification/`](../../../verification) Lake project models
project-owned transitions and proves stated invariants. Its generator emits
checked-in oracle tables; the script fails on drift and replays those decisions
against Elixir. `bin/setup --with-lean` prepares the toolchain.

Lean proves the model, not the complete BEAM implementation or every scheduling
interleaving. Finite oracle replay connects selected implementation behavior to
the model. Keep each model's scope and uncovered cases explicit.

## Bounded load checks and evidence

`bin/sts-call-load smoke` runs the comparative local lane; `measured` requires a
quiet window without competing compiles/tests. It compares real compiled room
paths with synthetic model/audio workloads, including overlapping turns, failure
isolation and cleanup. Keep latency samples, drop counts and host/scheduler details.

These measurements are regression evidence, not hosted model latency, production
capacity or carrier audibility. A small sample's p99 may simply be its maximum.
Do not weaken deadlines or remove failure assertions to make a load run pass.

Record commands, outcomes, failures and limitations in labnotes. Milestone checkboxes
mean their acceptance gates passed; a design review or a Storybook approval does
not complete implementation.
