# Room-owned STS external and hybrid turn control

Status: design candidate with three unresolved prerequisites from independent
review. This is not approved implementation or acceptance evidence. The
milestone tracks those separately.

## Decision

The selected human STT stream is the first candidate room activity source for
external and hybrid STS. Its `turn_started`/`turn_ended` signals are activity
evidence, not response text. The room must forward admitted external starts and
ends in order through the existing capability `input_activity/2` path. Hybrid
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
`ResponseOrigins.prepare/1` currently skips those checks for descriptors
without response-start context support. A busy or rejected boundary does not
count as delivered and must not unlock a response. Separate STT/STS ingress
lanes have no common source-frame watermark today. Late STT detection relative
to already accepted later PCM needs explicit test evidence; message ordering
alone does not solve it.

The human-STT publication path remains the sole public caller-turn owner when
human STT is selected. Forwarding activity may prompt or end an STS response,
but cannot publish a second caller pair or trigger a second room interruption.
STS response and playback stay under the existing authorization and egress
fences. A delayed human-STT onset must not cancel a newer STS reply.

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
and direct `input_activity/2` does not revalidate authority for descriptors
without response-start context support. The milestone records these as open
prerequisites. The controller design is not approved until they are resolved
with focused evidence.

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
