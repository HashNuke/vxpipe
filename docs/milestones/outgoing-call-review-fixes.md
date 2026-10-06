# Outgoing call review fixes

Status: complete (2026-10-06). The six corrections are committed as `817453a4`;
twenty consecutive directional live cases and all final local gates pass.
Prerequisite: [Outgoing calls and two-call live
telephony](outgoing-calls-and-live-telephony.md), whose implementation was reviewed on 2026-10-06
and is committed as `b1fd2f57`.

## Review summary

At review, the milestone's checklist was substantially implemented: schema direction and compatibility,
plan/persistence fields, engine dial lifecycle, gateway outcome propagation, the API with
idempotency, observability, provisioning and live harness. Focused suites passed (direction and
room 36, Calls 7, Gateway HTTP 9, Persistence 19, Gateway telephony/providers 199, shell suites).

It was incomplete. A live rerun on 2026-10-06 failed the Telnyx -> Twilio answered case in
4 of 9 runs (3 of 5 with a cold Funnel, 1 of 4 with `tools:up` kept warm), contradicting the
milestone's "complete" status. Six defects are reproduced below by automated tests that fail on
the reviewed tree. Five reproduction files cover six issues; issues 3 and 4 share one file.
The original isolated `*_review_test.exs` reproductions are retained with focused extensions;
owning suites also cover the repaired contracts. All review tests and existing suites are green.

Reproductions:

| # | File | Test |
| --- | --- | --- |
| 1 | `apps/vxpipe_call_engine/test/vxpipe/call_engine/outgoing_call_review_test.exs` | a hangup after a physical answer awaiting machine classification is not rejected |
| 2 | `apps/vxpipe_gateway/test/vxpipe/providers/telnyx/webhook_decoder_review_test.exs` | a callee decline (call_rejected) normalizes to a remote hangup, not a failure |
| 3, 4 | `apps/vxpipe_calls/test/vxpipe/calls/outgoing_call_review_test.exs` | no outbound number cannot be published; human `handled_by` rejected |
| 5 | `apps/vxpipe_gateway/test/vxpipe/gateway/http/outgoing_calls_review_test.exs` | replaying a failed outgoing call with the same key is not reported as success |
| 6 | `apps/vxpipe_gateway/test/vxpipe/gateway/telephony/outgoing_leg_review_test.exs` and the live Telnyx -> Twilio case | an answer webhook arriving while the dial request is in flight is not lost |

## Issue 6 (highest): Telnyx outgoing-leg webhooks rejected; answered calls end `no_answer`

Observed live (`bin/livetests run --only live_telephony_telnyx
apps/vxpipe_console/test/integration/live_telephony_test.exs`): the Twilio side answers, its room
attaches media and speaks, but the Telnyx outgoing room records `outgoing_outcome: no_answer`
after the ring deadline. The HTTP boundary counts show three `503` responses on
`telephony_webhook` in that run. `Vxpipe.Providers.Telnyx.Events.dispatch/5` answers 503 for any
`IngressHandler.dispatch/4` error and discards the reason, so the logs show nothing.

Reproduced mechanism: `OutgoingLeg` submits the carrier dial inside `handle_continue(:dial)`, so
a webhook for that leg dispatched while the dial request is in flight waits behind it in a
`GenServer.call`. If the dial outlasts the dispatcher's timeout (`CallIngress` 5 s), the webhook
gets `{:error, :telephony_leg_unavailable}` -> 503 and the answer never reaches the room. The
reproduction scales the timeout down to 200 ms. The live root cause is not yet proven to be only
this mechanism; another failing run showed Telnyx answered but the Twilio media WebSocket never
arrived (incoming call stuck `admitting`, all three Funnel relays timing out on initial health).

Tasks:
- [x] Record the dispatch error reason (bounded, no payload) in telemetry and logs for every
  non-2xx telephony webhook, for both providers.
- [x] Rerun the live Telnyx -> Twilio case until a failure captures the reasons; record them.
- [x] Make outgoing-leg event handling independent of the in-flight dial: submit the dial off the
  leg's GenServer loop (for example a supervised task replying to the leg), and accept or buffer
  identity-matched events received before the submission result. Keep the existing
  late-acceptance and unknown-submission behavior.
- [x] Make reproduction 6 pass; add an equivalent case for Twilio status callbacks.
- [x] Live harness: before dialing, require every public relay address from DNS to serve
  `/healthz` (or a bounded stable window), not just one; carriers may reach any relay.
- [x] Acceptance: 10 consecutive passing Telnyx -> Twilio and Twilio -> Telnyx live runs with
  `bin/livetests run --only live_telephony ...`; record counts and any residual failures. Until
  then the parent milestone is not complete.

## Issue 1: hangup during machine detection after answer recorded `rejected`

With machine detection pending, the gateway reports `:connected` (carrier answered). A remote
hangup then reaches `OutgoingCall.report/4` with `outcome: nil`, and `normalize(:hangup)` records
`rejected`, which the spec reserves for a hangup before answer.

- [x] Track the physical answer (`:connected`) separately from the media-verified answer so a
  later end records `answered` (with `answered_at`), not `rejected`; keep `machine` for a machine
  result. Make reproduction 1 pass.

## Issue 2: Telnyx decline (`call_rejected`) recorded `failed`

`WebhookDecoder.end_reason/1` maps Telnyx `call_rejected` to `:failed`; the outgoing spec defines a
remote hangup before answer as `rejected`. Telnyx's documented causes are `call_rejected`,
`normal_clearing`, `originator_cancel`, `timeout`, `time_limit`, `user_busy`, `not_found`,
`no_answer`, `unspecified`.

- [x] Map `call_rejected` to `:hangup` (the engine derives `rejected` before answer). Update the
  existing decoder test that asserts `:failed`, and make reproduction 2 pass. Confirm transfer
  outcomes still read correctly.

## Issue 3: outgoing spec on a service without an outbound number publishes

`OutgoingLegDialer.validate/3` requires `service.outbound_number`, so such a spec publishes and
claims, and every request then fails at dial time with a retryable 503
(`outgoing_call_start_failed`).

- [x] Reject publishing (and claiming) an outgoing spec whose callee service has no outbound
  number, with the existing safe error shape at the service path. Make reproduction 3 pass and
  update fixtures that relied on the missing number.

## Issue 4: outgoing spec accepts a human `handled_by`

The outgoing API creates no route or join token for a human handler, so the callee would answer
into a room nobody can join.

- [x] Require `outgoing_call.handled_by` to be an agent (the spec's "usually an agent" was too
  loose; human handlers would need a separate join design). Make reproduction 4 pass and update
  `docs/call-spec-direction.md`.

## Issue 5: replay of a failed outgoing call answers 200

A failed start answers 503 with `"retryable": true`; repeating it with the same
`Idempotency-Key` answers `200` with `state: "failed"`, a success status for a call that never
connected, so the advertised retry can never succeed.

- [x] Choose and document one contract: either replay the original failure status and body for
  the same key (and say a new key is required to retry), or allow a same-key retry after a failed
  start to create a new attempt. Do not return 2xx for a failed attempt, and make `retryable`
  consistent with it. Make reproduction 5 pass and update the implementation's existing
  "replay never redials" test accordingly.

## Process notes

- [x] Commit the reviewed implementation as coherent checkpoints, then these fixes; keep the
  parent milestone's status and index entry at incomplete until Issue 6's acceptance passes.
- [x] Add this milestone to `docs/milestones/index.md` after the parent entry.
- [x] Root gates and Lean as `AGENTS.md` requires; earlier full-suite failures remain recorded
  in the parent milestone.

## Design review (2026-10-06)

The prerequisite is the existing parent implementation, not a completed parent acceptance
gate; that gate is reopened. Diagnostics and live failure capture precede the dial-loop
change. Focused regression contracts precede each behavior repair, then owning suites,
all-relay preflight and the paired ten-run acceptance precede any completion claim.
The six user-approved corrections fit the current direction, credential locking, initial
leg ownership and idempotency contracts. Physical answer evidence requires an additive
persistence constraint migration so a later machine classification retains `answered_at`.
Human outgoing handlers remain out of scope pending a separate join design. Same-key
failed starts replay their original nonretryable 503; another attempt needs a new key.
The concurrency and migration decisions are recorded in
[outgoing runtime](../outgoing-call-runtime.md#review-correction-physical-answer-dial-concurrency-and-failure-replay).
This design review is separate from implementation and live acceptance progress.

## Verification evidence (2026-10-06)

All six original reproductions failed on the reviewed implementation. Additional focused
red cases cover physical-answer timestamps, failure retryability, all-relay readiness,
Twilio callbacks during a blocked dial, a buffered answer following unknown REST, and
machine projection through both ordinary end and archive closure. The repairs preserve
existing incoming, transfer, usage, timeout and late-adoption behavior.

Before concurrency changes, a cold preflight failed with all three relays closed (seed
105400), submitting no call. A bounded warm capture then selected only Telnyx → Twilio:
seed 197656 failed reciprocal audio after receiving Deepgram TTS `session_failed` /
`provider_failed`; both carrier sockets started, physical answer was retained, five Telnyx
webhooks returned 200 and no webhook failure was recorded. Seeds 990489, 541361, 168143
and 284967 passed. Thus this captured live failure is a separate provider/media failure;
it does not prove the blocking dial is the only live root cause. The scaled 200 ms blocked
dial regressions prove that mechanism deterministically for both carriers. Only the
selected telephony cases ran; no number purchase or environment-file inspection was used.

The live reliability gate below and all final local gates pass: formatting,
warnings-as-errors compilation, strict Credo, unused-dependency checking and Lean
build/oracle/replay. The final full umbrella run reports **3,192 tests, zero failures,
104 excluded**, seed **394892**. Earlier full runs hit the
previously recorded WebRTC 1750 Hz assertion or a phone-harness recovery timeout;
all review regressions passed. A focused mock-provider fragment test failed red then
passed after completing any earlier Speak through the ordinary test transport path.
Both complete carrier harnesses passed, and five selected storage-loss repetitions
passed. This fixture repair is not claimed to establish the intermittent timeout's cause.

The repeated WebRTC 1750 Hz failure was isolated separately: bounded packet diagnostics
proved the observer's audio reached the receiver but decoded with excessive energy and
insufficient tonal purity. The receiver fixture recreated its Opus decoder between
assertions on the same ongoing stream. Retaining one decoder across cue/conversation
checks, basic packet reads and drained frames made the same red case pass six consecutive
executions with seed 394892. Temporary diagnostics were removed; frequency thresholds,
amplitudes, timeouts, sender pacing and production media policy were unchanged. The passing
final umbrella check includes this minimal fixture correction and all 562 Gateway cases.

## Current live acceptance (2026-10-06)

After the concurrency and relay fixes, ten consecutive paired selections passed: **20
answered calls, ten Telnyx → Twilio and ten Twilio → Telnyx, zero failed acceptance cases**.
Each case proves signed ingress/media, reciprocal remote greeting transcripts, both rooms
ending and both durable archives closing, and answered outcome with all three dial times.
Every advertised DNS relay served gateway health before each dial. The parent-owned tools
node remained warm between pairs and stopped on exit; no purchase or personal destination
was used. Only these two tags were selected:

```shell
bin/livetests run --only live_telephony_telnyx --only live_telephony_twilio \
  apps/vxpipe_console/test/integration/live_telephony_test.exs
```

| Pair | Seed | Directional results |
| --- | --- | --- |
| 1 | 255177 | Both passed |
| 2 | 410943 | Both passed |
| 3 | 821371 | Both passed |
| 4 | 514722 | Both passed |
| 5 | 962698 | Both passed |
| 6 | 867136 | Both passed |
| 7 | 857949 | Both passed |
| 8 | 80582 | Both passed |
| 9 | 379702 | Both passed |
| 10 | 236367 | Both passed |

Residual diagnostics: several selections recorded HTTP 503 `leg_not_found` callbacks
despite successful acceptance. These counts are retained below; they are not relabelled
as a clean webhook boundary or claimed to be dispatch timeouts. No
`telephony_leg_unavailable` failure was recorded by the successful selections. The earlier
pre-concurrency Deepgram TTS failure is retained in the baseline evidence.

| Pair | Telnyx `leg_not_found` 503 | Twilio `leg_not_found` 503 |
| --- | --- | --- |
| 1 | 0 | 1 |
| 2 | 3 | 1 |
| 3 | 3 | 1 |
| 4 | 0 | 1 |
| 5 | 0 | 1 |
| 6 | 2 | 1 |
| 7 | 3 | 1 |
| 8 | 3 | 1 |
| 9 | 3 | 1 |
| 10 | 3 | 0 |
| Total | 20 | 9 |
