# Outgoing room runtime preparation

Read the D3–D4 contracts and their engine/Gateway boundaries while the D1–D2 umbrella
suite completed. No runtime code changed in this labnote's checkpoint.

- Startup installs the handler after asynchronous capability preparation. A dedicated
  initial-dial module can start after install; using transfer preparation would incorrectly
  make the callee a private transfer destination.
- The outbound resolver currently accepts transfer admission only. Initial admission must
  be restricted to the outgoing plan's exact callee while preserving protected destinations
  and pinned service references.
- Gateway's outbound session attachment already uses ordinary room connection admission
  when no transfer is pending. Its unconditional media-ready/DTMF transfer-control reports
  still need direction-specific handling.
- The connector currently hides the distinction between accepted and unknown submissions.
  The initial-call path needs a provider-neutral submission result without changing existing
  transfer behavior or retrying an uncertain carrier request.
- Outgoing leg owners currently exit normally after authenticated ended events, losing the
  normalized reason. The room needs correlated outcomes and an owner monitor; the leg also
  needs structural room-ownership cleanup for room loss during ringing or submission.
- Startup readiness currently accepts any connected media and has its own deadline. Initial
  outgoing readiness must require the callee, and its preparation/media budget must account
  for ring time up to 60 seconds. The ring timer must retain one deadline from dial submission
  through callee media readiness, independent of duplicate/late callbacks.
- Native STS generated opening currently returns first_message_unavailable. The outgoing
  generated default needs explicit treatment before claiming native STS acceptance; the
  approved Gemini LLM plus Deepgram STT/TTS live lane avoids relying on that existing gap.

Next red cases: preparation before exactly one dial, normal callee media before opening speech,
deadline cleanup, normalized non-answer outcomes, unknown submission without redial, and room
loss while submission is pending. Keep these separate from API/idempotency tests. No provider
API request or live call was made during this research.

## Runtime implementation (2026-10-05)

Wrote and ran ten focused engine cases before implementation. After correcting a test
struct pattern that could not compile before the new fields existed, all ten failed on
the expected boundaries: receive-only startup and transfer-only destination resolution.
Added initial request purpose/room ownership/attempt correlation, a room-scoped single-dial
task supervisor, and a dedicated OutgoingCall coordinator. Preparation precedes the dial;
submission runs outside RoomAuthority. Callee media uses main admission, and readiness
requires the callee plus accepted submission before starting first-message speech.

Follow-up red cases exposed an early greeting while submission was pending, missing answer
reports, and the readiness timer expiring before a 60-second ring budget. Those cases now
pass. A controlled-clock red case proved that a delayed answer could bypass an elapsed
deadline before its timer message arrived; callbacks now also check the absolute deadline.
Early media during handler preparation is reconciled when the submission is accepted.
Unknown submissions end without retry; failures and normalized non-answer reasons end
the room through its significant authority exit. Ring cancellation is idempotent, and stale
timer messages cannot end an answered call.

Gateway red cases covered outcome correlation, answer deduplication, unknown submission,
room-owner loss and late identity cleanup. Its InitialLegLifecycle monitors the room and
separates initial cancellation from transfer behavior. Unknown initial owners remain available
for a bounded media-token lifetime, so a late authenticated identity can be hung up without
redialing. Another red case exposed that the connector killed a blocked submission owner
on timeout, losing late acceptance cleanup. Initial timeout now returns unknown and initial
disconnect is asynchronous; the owner processes cancellation once the bounded provider
submission returns. Transfer behavior retains its existing synchronous path.

The carrier media test initially omitted the provider connection identity; corrected that
fixture before confirming the intended failure, transfer_not_pending. Initial media no longer
requests transfer acknowledgement, and DTMF 1 does not require transfer acceptance. The test
also initially asserted an absent field on ConnectionAttachment; corrected it to compare the
binding incarnation and verify main admission/no transfer attempt on the actual attachment.

Configured AMD now distinguishes physical connection from definitive answer. It holds media
until human/unknown classification; machine classification ends the attempt before media
attachment or greeting. Unknown classification permits the call without claiming human proof.
Engine tests verify a connected call can still finish with the machine outcome while classification
is pending. Disabled AMD keeps the ordinary answered/media path.

Strict Credo found the new callbacks crossed the 800-line boundary in PlanStartup and
RoomAuthority. After focused tests were green, extracted entry connection/transport validation
and moved process-down handling to its existing owner. No speech source-cutover module changed.

Focused verification: 64 engine tests (outgoing, lifecycle, transfers and opening audio), zero
failures; 27 Gateway outbound-leg tests, zero failures. Format, compile with warnings as errors,
strict Credo, unused dependency check and git diff whitespace checks passed. The full umbrella
suite is running; do not mark its acceptance as passed before its terminal result.

Remaining contracts are still open: native STS generated first-message support, initial submission
acknowledgement for the HTTP workflow, durable outgoing outcome/timestamps and details/inspection
projection, the authenticated published-spec/idempotency API, and bounded live carrier acceptance.
No live call, paid AI/speech test, purchase or credential-file read was performed in this runtime
checkpoint. Existing unrelated worktree changes were preserved; no commit was requested.

Full root regression finished successfully: 3,078 tests, zero failures, 98 excluded across
all nine applications, seed 870030. Gateway: 532 tests, zero failures, 477.9 seconds. All other
root gates passed. D4 is accepted; D3 remains open for native STS generated opening.
