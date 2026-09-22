# Finite agent-output recognition settlement

Decision, 2026-09-22: one generated reply is one finite recognizer allocation.
Existing STT `turn_ended` events terminate recognition segments, not the finite
input stream. Accumulate their final texts in event order, once per turn reference,
with a space between nonempty segments. Cumulative interim transcripts are not
additional segments. Bound retained finals to 64 references and 65,536 UTF-8
bytes including separators; exceeding either bound fails recognition honestly.

The optional STT `finish_input/1` callback accepts finalization; `:ok` alone is
not completion. A supporting provider emits a new ordered, fieldless STT event
`:input_finished` only after all finals for the accepted finite input are emitted.
This event uses the existing allocation identity, channel order and acknowledgement
boundary. No later audio is fed into that allocation. The consumer accepts this
terminal marker only after STS generation ends, then freezes the aggregate and
retires/replaces the recognizer before another generated reply can use it. Late
events on either side of retirement cannot contaminate the next reply. Playback
and policy still gate publication; recognition completion alone publishes nothing.

The local Morse adapter can prove this synchronously after decoder flush and
ordered final emissions. Hosted providers without an implemented finite-input
terminal proof remain unsupported for successful finite recognition; they must
not infer completion from a conversation endpoint. Existing human STT behavior
does not invoke this optional operation and is unchanged. The existing failure
deadline means failure, never successful finality. Restart bounds, private startup
options, PCM checks, usage identity and accepted-byte accounting remain unchanged.

Recognition's existing budget starts when both generation and playback are done
and finite recognition is still pending; it does not bound the preceding playback
wait. Store its absolute monotonic expiry when arming the timer, and check that
expiry after acknowledging terminal proof, before accepting successful recognition.
A terminal queued before the timeout notification but processed after expiry is a
timeout: failed recognition usage, no transcript, and recognizer retirement. Timer
mailbox order cannot extend the budget. This preserves the recognition start point
and does not alter the separate provider-transcript generation-started deadline.

Rejected alternatives:

- First/last observed `turn_ended`: no proof that another segment is not pending.
- Callback `:ok` as completion: providers may accept work before asynchronous
  results reach the channel.
- Quiet-period or new timeout: elapsed silence cannot prove upstream completion.
- Reuse the successful allocation without a terminal protocol: permits old
  endpoints to acquire the next generated reply's identity.
- Provider transcript fallback: violates the pinned transcript source.

This extends only finite-input STT evidence, not conversational endpointing,
Google STS control, output transcript settlement, egress or playback semantics.
No hosted protocol support or full milestone acceptance is claimed.

Admission amendment following parent review: add `finite_input?: false` to the
validated descriptor, legal only for STT. Supporting providers explicitly declare
true and implement `finish_input/1`; only those descriptors may emit
`input_finished`. PlanStartup rejects selected output recognizers without this
capability before credential lookup/allocation; direct sidecar allocation also
rejects it. Human conversational STT does not require this flag. Existing Google
private configuration must still be retained/redacted through the ordinary STT
runtime, but Google cannot be admitted as a finite sidecar without terminal proof.
Hosted finite-input support remains an explicit uncompleted milestone requirement,
not a removed requirement or a timer-based approximation.

After the first 46-test green checkpoint, extract recognizer allocation and
finite-input callback invocation into `OutputRecognizer`: the new behavior pushes
Output past its existing 800-line limit. Keep coordination in Output and bounded
text accumulation in OutputRecognition. This is an ownership refactor, not a new
session scope, scheduler, credential resolver or provider abstraction.
