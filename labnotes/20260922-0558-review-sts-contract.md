# Review STS checkpoint A (2026-09-22)

## Scope

Reviewed `a31a479f` and `9fc90819` against checkpoint A of
`labnotes/milestones/agent-speech-to-speech.md`. The worktree was initially clean.
This is a review, not implementation of checkpoints B–F. No application source,
existing tests, milestone checklists or commits were changed.

Morse STS currently acknowledges binary input and provides allocation lifecycle
only. It does not decode input or generate a reply. Therefore an STS call/audio
round trip or ten conversational STS calls cannot yet run. Existing text-model
Morse call tests exercise a different response path.

## Findings

1. Existing persisted calls lose call inspection after upgrade. Prepared plans
   are stored as Erlang external terms, so existing `ResolvedCallPlan.Capabilities`
   values contain only the previous three fields. `ResolvedPlanCodec.decode/1`
   preserves that old shape. The newly added direct field access in
   `CallInspectionPresenter.capabilities/1` raises `KeyError` for
   `:speech_to_speech` (and would similarly fail for `:output_speech_to_text`).
   A Console regression probe reused the existing presenter fixture, removed
   only the two new capability fields to reproduce the old serialized shape,
   encoded and decoded through the real codec, then called `present/1`. It
   failed at presenter line 176. This affects old text-model calls even with
   STS disabled. Normalize absent fields to nil at durable decode and test
   this upgrade boundary; recompiling a fresh call spec does not exercise it.
2. The advertised STS output contract cannot carry output. An independent test
   provider implementing all seven callbacks starts, binds, publishes readiness,
   accepts input and emits an acknowledged `:speech_started` event. Calling
   `Speech.Channel.submit/3` from that bound provider for the turn returns
   `{:error, :stale_request}`. `OutputState.prepare_audio/5` needs an admitted,
   submitted request; the sole admission path is `Session.speak/2`, which rejects
   STS, and `Event.supported?/2` limits `:input_submitted` to TTS. There is no
   native STS output admission path. Input/output transcripts also share one
   undifferentiated event, and the closed event vocabulary has no STS tool or
   interruption events. Checkpoint B owns the Morse implementation and room
   integration, but checkpoint A explicitly owns this shared contract.
3. STS descriptors lack the admission facts promised in A. Starting with
   `MorseCodeSTS.Session.configure([])`, replacing `settings` with `%{}`,
   `endpointing` with `:none` and `speech_start?` with `false` still passes
   `Descriptor.validate/1`. The descriptor contains no required input/output
   transcript coverage, output-text settlement, supported turn-control or
   interruption/history-reconciliation facts. Compiler response-path validation
   checks presence/exclusivity only; it cannot enforce the selected participant
   transcript requirements without these facts.
4. External and hybrid turn control compile and configure successfully, but
   `STSProvider` has no `input_activity` callback and `Speech.Session` has no
   ordered activity command. Morse returns the same provider-gap endpointing
   descriptor for all three modes. The source-ref omission documented in the
   previous labnotes does not account for dropping the whole activity operation.
   The contract must define and exercise it, or reject unsupported modes.

The contract findings concern requirements marked complete in checkpoint A. The
absence of the Google adapter, room STS controller, actual Morse conversation,
tools/transfer implementation and frontend work is expected at this checkpoint.
Hosted STS remains gated; the contract failures do not demonstrate a live STS
failure, while the separate stored-plan regression affects existing inspection.

## Verification

- Child Call Engine call-spec, speech and startup tests: **219 tests, 0 failures**,
  seed 734648.
- Temporary Console upgrade probe: **1 test, 1 expected failure**,
  `KeyError` at `CallInspectionPresenter.capabilities/1`, after a real
  `ResolvedPlanCodec.encode/1` / `decode/1` round trip. Repeating the identical
  probe with the presenter source from `HEAD~2`, loaded under a temporary
  module name, passed (**1 test, 0 failures**); current fixture/codec unchanged.
- Temporary independent provider and adversarial contract probes: assertions
  reproduce missing descriptor validation, missing activity callback and rejected
  credited output. A fourth diagnostic confirms a transcript direction field is
  rejected; the specific field name is illustrative, while the absence of any
  defined role/direction is established by the closed event schema.
- Ten concurrent owned Morse STS allocations, synchronized after readiness,
  each submitted 100 PCM chunks of 320 bytes: **1,000/1,000 accepted**. One
  provider was killed; the other nine finished. All ten trees and providers
  were monitored to termination; later input was rejected and close was
  idempotent. Maximum sampled mailbox length after admission was zero. This is
  a lifecycle/admission probe, not speech generation, pacing or call quality.
- Probe used two BEAM schedulers. One sample, while the umbrella suite was also
  running: startup p50/p95/p99 94.914/95.059/95.059 ms; input admission
  0.031/0.112/6.611 ms; cleanup 0.580/6.952/6.952 ms. Startup/cleanup have only ten
  observations. These are smoke-test measurements, not latency acceptance claims.
- Root format check, warnings-as-errors compile, strict Credo and unused-lock
  checks passed. Credo checked 1,045 source files and reported no issues.
- Initial root `mix test` could not authenticate PostgreSQL over TCP because
  the test configuration had no password. Verified the existing local socket
  connection, then reran with `PGHOST=/var/run/postgresql`; no credentials or
  database configuration were changed.
- Full umbrella suite: **2,033 tests, 0 failures, 42 excluded**, seed 728487,
  exit 0. Counts by child: MCP 37, AgentRuntime 95, Providers 18, CallEngine 890,
  Calls 119, Gateway 480, Artifacts 20, Persistence 184, Console 190. Gateway
  took 461.4 seconds, including the default-lane Morse/WebRTC checks. The
  existing suite does not cover the reproduced old-plan inspection regression.
- No hosted provider calls or billable tests were run. No rendered-browser
  verification was performed: the reviewed presenter adds labels, but there
  is no runnable STS room/UI flow at this checkpoint.

## Review artifacts

Adversarial ExUnit probes and raw test output were kept in a temporary directory
outside the repository, so intentionally failing review probes do not enter the
default suite. The only worktree addition is this labnote.
Final status/diff checks confirmed the reviewed commits and application files
were unchanged, with no whitespace errors in the review artifact.
