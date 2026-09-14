# Whole-room human handoff readiness

## Scope

Extend ordinary native human handoffs to delay the destination recognizer, a remaining human's
recognizer and a room recording writer independently. Each becomes the final blocker with
custom or nil waiting, followed by cues and actual conversation. Retain existing room/media
instances and reject held input without replay. No sample UI changes are needed.

## Reproduced attachment gap

The first three native custom-wait cases failed before transfer: the additional planned human
joined and attached successfully, but its selected STT transport never started. Initial startup
stores runtime selections only for its entry caller/receiver. Ordinary connection attachment
looked up that map and treated a missing entry as no STT, even when the pinned participant
selected a recognizer. This would also leave whole-room readiness unable to prepare that input.

Two focused engine cases reproduce the contract directly. A supported selected profile returned
an attachment with nil ingress; an unavailable selected profile incorrectly returned success.
After the fix both cases pass. Fixture mistakes in the first engine red attempts (a string map
key and the existing attach helper's arity) were corrected before confirming those expected failures.

## Decision and implementation

Keep entry speech under initial startup and existing transfer-private preparation unchanged.
For another admitted planned human, connection selection returns the existing protected plan/runtime
context and participant to RoomSupervisor. It resolves only that participant's STT configuration
outside RoomAuthority, then uses the existing supervised capability/ingress and policy-binding path.
No provider starts merely because the participant exists in the definition or joins the room.
Unsupported selected configuration uses the existing attachment-failure cleanup instead of silently
omitting STT. The original caller's speech, source model/voice and room services retain their bindings.

Rejected expanding initial startup to initialize every defined participant: it would make unused
profiles dependencies of calls that never use them. Rejected bypassing the gap with a second
connection for the initial caller: that would not prove another planned human's selected capability.
This is required groundwork exposed by the three-peer handoff, not a separate delivery phase.

## Verification

- Engine red: two selected-profile attachment cases failed for missing ingress / unexpected success.
- Engine green: both pass after deferred configuration selection.
- Native custom-wait cases: three pass after the attachment fix.
- Complete native matrix: nine pass (35 excluded), seed 235296, including the public HTTPS WAV.
  Each destination/remaining-human/room resource becomes the final blocker with custom/nil waits.
  Both existing audience listeners receive waits, all three receive ordered cue/conversation,
  held microphones are discarded, and later participant audio reaches STT and recordings.
- The controlled native acceptance item is complete: 22 checkpoint tasks remain.
- All five root gates pass: format, warnings-as-errors compilation, strict Credo,
  `mix test --max-cases 4 --seed 235296`, and unused-dependency check. The suite has
  1,380 tests, zero failures and 16 exclusions. Engine: 634; Gateway: 375 including 43 default
  native startup/transfer cases. The public-URL variant passed explicitly in the nine-case matrix.
- The prior intermittent recovery concern remains open; this passing run does not establish its cause.

Focused commands from their owning applications:

```shell
mix test test/vxpipe/call_engine/definition_driven_call_test.exs \
  --name-pattern 'additional planned human'
```

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --include integration --name-pattern 'human handoff gates' --seed 235296
```

Retained logs: `vxpipe-late-human-stt-red.log`, `vxpipe-late-human-stt-green.log`,
`vxpipe-whole-room-handoff-matrix.log` and `vxpipe-whole-room-handoff-gates-*`.
The development server was not restarted.
