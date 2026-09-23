# Room-owned STS external and hybrid turn control

Status: design candidate. Ordered ingress/capability authority and selected-STT
activity demand have focused local proof; controller retirement on demand loss,
producer provenance and provider hold-state retirement remain open. This is not
room-level implementation or acceptance evidence. The milestone tracks those
separately.

## Decision

The selected human STT stream is the first candidate room activity source for
external and hybrid STS. Its `turn_started`/`turn_ended` signals are activity
evidence, not response text. The room must enqueue admitted external starts and
ends through `STSIngress.activity/4`, which shares ordered credit with PCM and
delivers them to the capability's validated submission path. Direct
`input_activity/2` is rejected once a room ingress owns input. Hybrid
uses provider speech onset and human-STT end; it must not send a second start.
Provider-controlled mode must receive no external activity commands even when
human STT supplies caller text. Transcript-source choice remains independent of
this controller selection.

An external or hybrid selection without a selected human STT has no room activity
source today. Reject that combination at startup until a separate source detector
is designed and proven. Selection alone is insufficient: STT demand currently
follows transcript retention or live transcript recipients, so selected STT can
be dormant while STS remains demanded. Make controller activity an explicit
readiness/session demand independent of transcript publication, including when
transcript demand is removed mid-call, or reject/retire the selection before
readiness. Do not infer boundaries from transcript deltas, PCM arrival, or
silence. The provider descriptor must still declare and validate the selected
mode; the room cannot repair an unsupported provider configuration.

The current demand slice pins the entry caller and selected external/hybrid
entry receiver in the plan, then carries that agent identity into the STT
runtime, readiness inventory, capability and ingress. It requires source and
agent presence plus both audio routes, independent of transcript retention.
An audio-only route change closes or recreates the STT session even if the STT
transcript interval is unchanged. Closing a recognizer during an active turn
does not itself settle or cancel the room controller; that remains a separate
room-wiring requirement.

Prepared activity-only replacements need the same fence. A review probe
reproduced a retained prepared provider and `:preparation_conflict` after an
audio-only demand loss that left the transcript interval unchanged. The
preparation now compares selected-agent presence and both exact audio routes
before retaining a pending session; a focused test covers both invalidation
and unrelated membership rebase. Astra xhigh re-review independently verified
the original race, regrant and transfer refresh with no remaining reproduced
defect in this demand slice.

Only signals from the currently bound human STT capability and exact active
source connection may control STS. Require the selected STS capability, open
input epoch, same source identity, current presence, unheld source, and permitted
caller-to-agent audio route. Pin the accepted STT turn reference and its source
audio interval/lifecycle epoch at the producer, before asynchronous room
delivery; an end may close only that active pair. Current STT signals carry
only the STT transcript interval, which can remain unchanged across an
audio-only revoke/regrant. Stamping the room's current STS epoch when a delayed
signal is first handled would relabel old evidence. Add a producer-side fence
before enabling this path. Do not let an old end close a new start. Revocation,
hold, source replacement, capability replacement or handoff retires the pair
before any new controller interval. Unrelated global policy revisions must not
invalidate an unchanged source interval. Accepted boundaries must be sent to
the STS capability in signal order. STS PCM and controls share one
channel input slot; route controls through a bounded ordered admission/barrier
with the STS ingress rather than racing a direct capability call against
in-flight PCM. Revalidate source, epoch and policy at capability delivery;
`ResponseOrigins.prepare/1` by itself skips those checks for descriptors
without response-start context support; the new bound-ingress delivery path
therefore performs them before submission. A busy or rejected boundary does not
count as delivered and must not unlock a response. Separate STT/STS ingress
lanes have no common source-frame watermark today. Late STT detection relative
to already accepted later PCM needs explicit test evidence; message ordering
alone does not solve it.

Producer provenance remains unresolved. STT currently stamps a transcript
policy interval when it emits a signal; it does not carry the audio interval or
an STS lifecycle generation. A delayed signal cannot be assigned the room's
current STS epoch on receipt. Moreover, if transcripts still demand STT,
audio-route revocation may leave its provider session alive, allowing an old
provider boundary to first surface after regrant. The next design proof must
coordinate source-ingress admission, semantic-session retirement, frozen
signal provenance, and room comparison. Hold/release requires an equivalent
producer lifecycle fence before releasing the new STS epoch; a room-only
watermark cannot classify provider evidence that has not surfaced yet.
The [activity-provenance design](sts-activity-provenance.md) records the
allocation-bound signal and acknowledged PCM cutover requirements in detail.

The human-STT publication path remains the sole public caller-turn owner when
human STT is selected. Forwarding activity may prompt or end an STS response,
but cannot publish a second caller pair or trigger a second room interruption.
STS response and playback stay under the existing authorization and egress
fences. A delayed human-STT onset must not cancel a newer STS reply.

## Hold of provider-owned external activity

A focused Morse capability test reproduced a caller-visible stale reply:
after an accepted external start and `HI` PCM, the former capability
hold/release path blocked the old end while held but an end after release
prompted an old-input reply. The provider had retained its decoder, input turn
and external-start state. The interim fail-closed gate below now prevents that
reuse; it does not implement reusable active-turn hold.

The interim safety gate closes input admission and fences playback, then fails
the owned STS allocation closed whenever accepted external/hybrid input remains
dirty and a quiescent provider/native-event boundary cannot be proven. A
completed external end by itself is insufficient: an old native end can still
be queued behind hold and first handled after release. Track accepted PCM as
well as explicit starts so hybrid PCM-only input is covered. A settled-idle
Google session should remain reusable only when its provider-owned quiescence
and outstanding native-event state both prove the old origin retired. No
billable hosted check is implied by this local decision.

Reusable hold/release needs a later acknowledged input discard/reset plus a
barrier for already-emitted native events. Merely clearing Morse decoder
fields would leave an old end in the channel/capability queue; sending the
ordinary external `:ended` boundary would instead trigger the old response.
Fail-closed retirement sacrifices that interrupted STS allocation but prevents
relabeling its input into a new room epoch. The milestone keeps successful
hold/release acceptance open until reusable semantics are proven.

The interim local implementation performs that fail-closed check after ingress
hold and output fencing. A provider must synchronously report quiescence, and
the owning capability then asks the native channel to prove its event queue
has neither awaiting nor pending evidence and no input command in flight.
Morse regards accepted PCM or an external start as dirty until the matching
audio turn completes; unrelated text-tool completion cannot clear buffered
audio. A completed Morse output is retired only after exact local playback
settlement, so genuinely idle external input can hold and release. Google
reuses its settled-idle resumption predicate. A missing callback,
negative result, or unacknowledged native event ends the capability with
`:unsafe_hold`; a genuinely idle provider can still release. Focused Morse,
hybrid, Google fake-wire and queued-native-event tests pass locally. This
does not add reusable active-turn hold or hosted Google proof.

## Rejected alternatives

- Inferring external end from a final transcript conflates recognition latency
  with speech activity and can respond after hold or route denial.
- Sending the human-STT start into hybrid mode creates a competing onset; the
  provider is responsible for hybrid onset.
- Reusing provider-controlled detection when `external` is selected silently
  changes the call's response-triggering contract.
- Broadcasting every STT signal to any STS capability loses exact source,
  policy and lifecycle attribution.

## Independent design review

Codex Astra xhigh reviewed the candidate against the current readiness,
policy-interval, STT signal and STS capability paths. It found three unresolved
dependencies, not reproduced runtime defects: transcript demand may leave the
selected activity source dormant; an already-emitted STT signal lacks the
source-audio/lifecycle provenance needed after audio-only revocation or hold;
and the original direct `input_activity/2` did not revalidate authority for
descriptors without response-start context support. The ordered ingress and
capability-delivery prerequisite has focused local proof, but selected STT
demand and producer provenance remain open. Provider-side activity state after
hold also needs an observable-consequence test. The controller design is not
approved until these are resolved with focused evidence.

Final scoped Astra xhigh review of the ordered ingress/capability seam found no
remaining concrete defect after the five reproduced review findings were fixed.
The owning ingress/capability/origins group passed 87 tests on seeds 0 and 1,
and the reviewer ran eight additional in-memory probes. This clears only that
prerequisite, not the room controller or its remaining dependencies.

## Implications and verification

The room needs a bounded, single active controller association for the one
permitted human source, plus an explicit runtime/descriptor mode check. Startup
must reject a missing activity source, and readiness must demand that source
whenever its activity controls STS. Producer-side lifecycle/audio attribution
and delivery-side authority checks must precede accepted room wiring. Focused
compiled-room tests must first reproduce the absent boundary, then prove
external and hybrid response timing, one public caller pair, no duplicate
text-model response, and stale signal
rejection across hold/release, source replacement, and policy revoke/regrant.
Capability/session tests already prove the Morse boundary protocol; they do not
prove the room wiring. Provider-level late evidence first observed after a new
epoch and complete transfer/hosted acceptance remain separate milestone gates.
