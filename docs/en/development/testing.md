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

Keep parameterized tests small: generate a named test that passes its scenario
parameters to a shared function, rather than expanding a large body for every
combination. The WebRTC handoff cases previously drove the compiler alone to
roughly 1 GiB of heap while optimizing duplicated scenarios. Reducing test
concurrency does not remove that single-process compilation cost.

Test helpers that start calls under the application supervisor must register
cleanup for the exact room incarnation. A test process exiting does not stop
application-owned room trees. On a host also serving the app, run builds and
focused tests sequentially; the app container's memory limit does not constrain
host `mix` processes.

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

Telnyx numbers available to the test runner carry two stable tags.
`vxpipe-<machine>` identifies the machine, and `vxp-<machine>-test` marks the
number as eligible for its live tests. Provisioning keeps eligible numbers
assigned to `vxpipe-<machine>-test` and fills missing roles from active,
unassigned numbers carrying both tags. The runner tags new purchases with both.
Caller and receiver IDs are saved in the local `telnyx-profile.json`. The
Tailscale node and outbound profile use `vxp-test-<machine>`.

For a scheduled test window, `bin/livetests telnyx:numbers plan` counts eligible
numbers on `vxpipe-<machine>-qa`. Borrowing routes their incoming calls to the
test application until restoration. Both tags and unrelated tags stay in place.
For an existing deployment, rename the two Telnyx Call Control applications in
place and apply both tags to the intended numbers before using the runner.

```bash
(
  set -e
  trap 'bin/livetests telnyx:numbers restore' EXIT
  bin/livetests telnyx:numbers borrow
  bin/livetests run --only live_telephony_caller_recovery apps/vxpipe_console/test/integration/live_telephony_test.exs
)
```

The `live_telephony_playback_retry` selection uses the same two-number window.
It submits a completed callback command again and checks for a second distinct
signed completion. A fresh command on the same leg confirms that playback
and webhook delivery still work.

The `live_telephony_recovery_elevenlabs` selection exercises a real Scribe
socket failure and listens for the repeat prompt on the other Telnyx leg.
It runs with machine-owned numbers. The coordinated handset procedure below
is an optional listening check for prompt wording, timing, and audibility.

For an unattended answered fallback transfer, borrow the machine-tagged Telnyx
numbers with the restoration trap above and select
`--only live_telephony_automated_recovery_transfer` on the same file. This test
uses the first pool number as both the machine caller ID and the inbound
number. The second pool number receives the transfer. It injects room-media loss,
checks reciprocal speech after bridge, and waits for terminal usage and cleanup.
`bin/livetests telnyx:inventory` shows account counts and pool eligibility.

Both transfer lanes opt in to recording and retain a WAV for each named track in
`tmp/live-telephony/<run>/<call>/<incarnation>/<track>-<artifact>.wav`. The runner prints the
run directory. Each file starts at the track’s first accepted sample and includes
silence across internal gaps. Earlier runs remain available after a
failed test. The checkout already ignores `tmp/`. The original room's recording
ends when that room shuts down. In an automated transfer the machine caller
can continue recording carrier playback and the bridged conversation.

For a coordinated handset transfer window, set `VXPIPE_LIVE_HANDSET_WINDOW=1`
and select `--only live_telephony_handset_recovery_transfer` on the same file.
The handset lane receives calls on the test pool's designated receiver and uses the other number as its transfer destination. The test prints the inbound number's last four digits. An operator calls from
a separate handset and says “transfer test” after the greeting. The first dial
rings out. When the test reports ready for the second call, the operator calls
again and repeats the phrase. After the destination greeting, the operator
says “bridge test” to verify audio crossed the human bridge. Both destination
scenarios use the other machine-owned number. After hangup the runner waits
for managed cleanup and checks the original call's stored carrier usage. The
caller and linked destination each need one terminal observation from a
distinct carrier event in the same session. Ring-out expects a failed
destination attempt and an answered bridge expects a successful one.

After ring-out has passed, set `VXPIPE_LIVE_HANDSET_WINDOW=repeat_and_transfer`
with the same test selector to exercise recognition recovery and the answered
transfer on a single call. Say “transfer test” once after the greeting. As soon
as the agent says “You can interrupt me now,” speak over the rest of the
acknowledgment and ask “Do you service commercial properties?”
The runner closes the recognizer on that next open turn. Repeat the question
when prompted. Say “transfer now” after hearing one answer, then say “bridge
test” after the destination greeting. The runner checks the recovered turn,
one completed agent answer correlated to the question, and speech crossing the
carrier bridge. Record which prompts the caller actually heard, any overlap,
and the perceived silence separately.

For the caller-abandonment check, use `VXPIPE_LIVE_HANDSET_WINDOW=hangup_during_ring`
with the same selector. Call only when the runner announces readiness, say
“transfer test,” and stay connected through the transfer announcement. Hang up
when the operator signals that Telnyx has identified the linked destination leg.
The destination remains unanswered. The runner checks the abandonment journal
entry, final usage for both legs and completed cleanup. A bridge or callback
announcement fails this case.

A private journal records the original application IDs and number IDs before the
first assignment changes. After an interrupted run, use `restore` from the same
machine and branch. Each switch verifies the live application names, number tags
and assignment. A third-party reassignment requires operator reconciliation.

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

## Call recording media

The Matroska endpoint contract (`GET .../calls/:call_id/recording.mka`) is
covered at two levels. The endpoint test uses real tenant-scoped persistence:
two bootstrapped tenants, artifacts stored under one call, and the same call
id requested under the other tenant must return the generic 404. The S3 test
downloads through the production `S3ObjectReader` against a loopback
S3-compatible server and verifies an HTTP range straddling an audio block
boundary byte-for-byte.

The S3 test needs a local moto server and is excluded from the default suite:

```shell
moto_server s3 -p 18764
VXPIPE_TEST_S3_ENDPOINT_URL=http://127.0.0.1:18764 mix test \
  test/integration/recording_matroska_s3_test.exs --include integration --only s3
```

`VXPIPE_TEST_S3_ENDPOINT_URL` defaults to `http://127.0.0.1:18764`, so the
first command alone suffices for a server on the default loopback port. Each
run creates a unique bucket and deletes it with its objects on exit. `ffprobe`
is optional: when present, track codec and title assertions run, and
`VXPIPE_MATROSKA_EXPORT_PATH` keeps a copy of the download for manual
inspection. This lane never touches the protected live-provider credential
file.

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
