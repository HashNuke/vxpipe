# Verify STS repairs (2026-09-22)

## Scope and result

Reviewed the uncommitted repair on top of `9fc90819`, including the new
`Speech.STSInput` module, against the four findings in
`20260922-0558-review-sts-contract.md`. The previous agent's implementation,
tests, docs and labnotes were already dirty at review start and were preserved.
No application source or existing tests were changed by this review.

| Previous finding | Verification |
| --- | --- |
| Stored-plan inspection crash | Fixed. The original independent old-plan codec/presenter probe passes unchanged. |
| STS credited output unavailable | Still reproducible, for both audio-driven input and the newly acknowledged text-input path. |
| Missing admission facts | Fields and output-source selection checks added; the original incomplete-descriptor probe now passes. Remaining consistency/coverage defects are below. |
| Missing external activity operation | Fixed at the checkpoint-A contract boundary. Independent provider receives external/hybrid activity, audio and text in order. Actual response triggering remains checkpoint C. |

The repair labnote explicitly defers turn-keyed output credit to B. That is a
deferral, not a fix for the original output-contract finding. The milestone's
new statement that all four findings are fixed is not supported by the probes.

## Remaining and new findings

1. **No STS output admission exists.** The original independent provider starts,
   binds, acknowledges readiness, accepts audio and publishes speech-start
   evidence; `Channel.submit/3` still returns `{:error, :stale_request}`.
   A second probe calls `Session.push_text/2`, receives and acknowledges its
   `:input_submitted` event, then submits PCM using that exact request reference:
   the same failure occurs. `Channel.accept_event/2` delegates STS submission
   to `STSInput.accept_submission/2`, which returns unchanged state. No STS
   command creates `OutputState.request`, so the existing credit path cannot
   accept its audio. This is independent of the deferred Morse codec/room wiring.

2. **Submission deduplication is not implemented.** An independent provider emits
   `:input_submitted` twice with the same text reference during one `push_text`
   callback. Both emissions return `:ok`. `STSInput.accept_submission/2` only
   checks that the reference matches the current input command; it does not
   record the first acceptance. Both events enter the semantic queue. This
   contradicts the newly documented stale-duplicate contract. Track consumed
   submission evidence and test duplicate emission before the callback returns.

3. **Generic transcripts bypass the new coverage gate.** An STS descriptor with
   both `input_transcript?` and `output_transcript?` false rejects the new
   directional event kinds, but emitting `:transcript` succeeds through the
   real bound channel. `Event.supported?/2` still unconditionally allows this
   undifferentiated STT event for STS. Restrict it to STT so an STS provider must
   use the explicit, coverage-gated direction and cannot undermine source
   selection or attribution.

4. **Contradictory provider turn mode passes descriptor validation.** Changing a
   valid Morse descriptor to `turn_control: "provider"`, `endpointing: :external`
   and `speech_start?: false` still validates. The exception for absent activity
   evidence checks `endpointing`, not the selected control mode; meanwhile the
   input channel correctly refuses external activity in provider mode. This
   admits a configuration requiring an input operation that the selected mode
   forbids and contradicts the guide's provider-mode speech-start requirement.

5. **The tool-call event cannot carry tool arguments.** Its closed field list is
   only `call_ref`, `tool_name` and `provider_request_id`; there is no payload
   or active-turn association. A `lookup_order` call containing an order ID
   and turn reference is rejected by `Event.build/2`. The particular proposed
   argument field name is not material: no defined field can carry the arguments
   needed by a parameterized tool, and the provider has no separate approved
   argument-delivery operation. The actual tool runner belongs to C, but A's
   provider contract must represent its request with bounded, validated data.

## Verification evidence

- Focused Call Engine call-spec, speech and startup tests: **228 tests,
  0 failures**, seed 924291.
- Original stored-plan Console regression probe: **1 test, 0 failures**,
  seed 0. It uses the original serialized three-field capability shape and
  the real durable codec before rendering the inspection response.
- Independent STS contract probes: **8 tests, 6 failures**, seed 0. The
  original incomplete descriptor and newly ordered activity tests pass. Two
  output probes plus duplicate submission, generic transcript bypass,
  contradictory descriptor and tool arguments reproduce the five findings.
- Ten concurrent Morse STS allocations in hybrid mode: **1,000 audio chunks,
  1,000 text submissions and 2,000 activity boundaries accepted**. Every text
  submission event was acknowledged. One provider was killed; the other nine
  finished. All trees/providers were monitored to termination, late input was
  rejected, and close stayed idempotent. Maximum sampled mailbox size was zero.
  Two BEAM schedulers; one sample concurrent with the umbrella run: audio
  admission p50/p95/p99 0.021/0.078/2.644 ms, startup 19.720/19.800/19.800 ms,
  cleanup 0.102/9.747/9.747 ms. This tests lifecycle/input admission, not generated
  speech or ten real calls.
- Root format, warnings-as-errors compile, strict Credo and unused-lock checks
  passed. Credo checked 1,046 source files with no issues.
- Full umbrella run uses the existing PostgreSQL Unix socket through
  `PGHOST=/var/run/postgresql`: **2,044 tests, 0 failures, 42 excluded**, seed
  550231, exit 0. Counts by child: MCP 37, AgentRuntime 95, Providers 18,
  CallEngine 899, Calls 119, Gateway 480, Artifacts 20, Persistence 185,
  Console 191. Gateway took 468.1 seconds and includes the existing default-lane
  Morse/WebRTC scenarios. The six failing adversarial probes are not covered
  by this passing suite.
- No hosted/billable provider calls, browser verification or commits. Probe
  source and raw output remain outside the repository in a temporary directory.

## Worktree integrity

The tracked patch was captured at review start and compared byte-for-byte after
the probes and after the full suite; it was unchanged. The untracked STSInput
source hash was unchanged. Only this new review labnote was added by the reviewer.
Final tracked diff and review-artifact whitespace checks reported no errors.
