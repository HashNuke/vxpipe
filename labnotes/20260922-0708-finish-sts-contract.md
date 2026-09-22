# Finish STS contract (2026-09-22)

## Scope

User authorized fixes for the five findings from
[`verify-sts-repairs`](20260922-0650-verify-sts-repairs.md). Work began with the
other agent's uncommitted repair in place; that patch was saved outside the
repository and preserved. No commit was requested or created.

## Red-green implementation

- Added an independent STS provider and five channel-level conformance tests.
  Initial result: **5 tests, 5 expected failures**, seed 0. They reproduced the
  absent output API, duplicate submission acceptance, generic transcript bypass,
  unusable tool arguments and contradictory turn-controller descriptors.
- Added `Session.admit_output/2` and `OutputTurn`, with STS admission/completion
  logic in `STSOutput`. Consumer authorization creates a fresh output reference;
  providers use existing bounded PCM credit without a TTS request. Generation
  completion, its acknowledgement and local playback settlement are distinct.
  Reusing a provider turn reference does not admit old generation output.
- The first green attempt exposed `JSON.encode/1` being unavailable in the
  installed Elixir. Used the standard `JSON.encode!/1` after bounded JSON-shape
  validation. Result: **5 tests, 0 failures**, seed 0.
- `STSInput` records consumed text-submission evidence during the callback.
  STS rejects generic `:transcript`; directional transcript events use coverage
  flags. Tools retain bounded JSON arguments and provider turn/call references;
  inspection omits arguments. Provider/hybrid modes require provider endpointing
  and speech-start evidence; external mode requires external endpointing.
- Added boundary tests for readiness/consumer authority, queued timeout, stale
  completion/settlement, provider loss with a surviving sibling, malformed and
  oversized JSON, and concurrent independent output sessions.
- Two additional red tests caught new-path integration gaps: non-PCM STS
  descriptors were accepted and a TTS-shaped settlement bypassed STS completion
  acknowledgement and playback bounds. Required linear16 in STS descriptors and
  rejected the TTS settlement operation on non-TTS allocations.
- An exact-65,536-byte tool argument test caught an overcount of array separators
  in the preliminary traversal budget. Made that budget a lower bound and kept
  the final encoded-size check authoritative, preserving acceptance at the limit.
- Kept the common byte ledger and extracted cohesive STS flow logic so Channel
  remains below the 800-line backstop (781 lines after formatting). The output
  path emits no fabricated TTS usage snapshots.

## Verification

- Focused speech plus STS call-spec selection: **161 tests, 0 failures**, seed 0.
- The concurrent test completed **10 allocations × 10 output turns** with audio
  and text input, one credited PCM chunk per output, generation acknowledgement,
  bounded playback settlement and explicit close. This tests the shared contract
  using deterministic PCM, not a Morse conversation or ten real calls.
- Initial root format check needed a second format pass for the new concurrent
  test. Formatting, warnings-as-errors compile, strict Credo (1,049 files) and
  unused-lock checks then passed.
- The first umbrella run (seed 156996) exposed a first-frame loss in the existing
  Flux `AudioTurnTest`. An isolated replay passed, and a full Call Engine replay
  passed **911 tests, 0 failures** at the same seed. Source inspection showed
  `StartupReadiness.complete/1` sent transport readiness before opening ingress.
  Added a deterministic test that holds ingress opening: it failed because
  readiness arrived during the hold. Moved input opening before the readiness
  notification, eliminating that ordering window without adding sleeps.
- First umbrella run completed **2,056 tests, 1 failure, 42 excluded**. Its only
  failure was the readiness race above; Gateway's existing default-lane
  Morse/WebRTC scenarios passed (480 tests, 7 excluded, 469.3 seconds). The final
  verification reruns the same seed with the deterministic regression included.
- Final focused repair check: **14 tests, 0 failures**, seed 0, covering both
  STS conformance/output suites and the repaired audio-turn readiness test.
- Compared the eight earlier-agent patches outside the corrected contracts/docs
  byte-for-byte with the saved initial diff: unchanged. Markdown local links and
  tracked patch whitespace checks pass.
- Final umbrella run: **2,057 tests, 0 failures, 42 excluded**, seed 156996,
  exit 0, using `PGHOST=/var/run/postgresql` for the existing local database.
  Child counts: MCP 37, AgentRuntime 95, Providers 18, CallEngine 912, Calls 119,
  Gateway 480, Artifacts 20, Persistence 185, Console 191. Gateway took 459.8
  seconds and includes the existing default-lane Morse/WebRTC scenarios.
- Final root `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict` and `mix deps.unlock --check-unused` all passed for the
  final source. Credo checked 1,049 files without issues. Final focused and full
  runs include the exact-limit JSON argument regression and readiness repair.

## Decisions and limits

The durable decision and rejected alternatives are in
[`docs/sts-output-admission.md`](../docs/sts-output-admission.md). The exact
protocol and a runnable independent-provider example are linked from the speech
author guide. Corrected the milestone's earlier all-fixed claim and annotated
the historical repair note rather than erasing the failed repair history.

Actual Morse response generation, room policy/sink/transcript integration,
interruption, tool execution, STS usage and hosted interoperability remain
checkpoints B–F. The milestone index stays unchecked. No hosted/billable calls
or browser changes were involved in this backend repair.
