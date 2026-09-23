# STT-owned activity provenance for room STS

Status: reviewed design candidate, not implemented room control. Selected-STT
demand, audio-route provider reset, and the ingress policy-interval proof are
committed enabling slices. Native allocation/input cutover, hold/release and
room acceptance remain open. Scoped capability-emission signal metadata and
recording-only retirement checks pass, but they are not a room controller
binding.

## Decision

Use one immutable activity binding per native STT allocation that is authorized
to control the selected room STS allocation. It records the exact STT source
connection/capability, selected STS capability and activation, STS input epoch,
and the source's audio-input and audio-output policy intervals. Native STT
`Event` already carries an allocation generation, producer sequence and native
turn reference; preserve those values, with the binding, in private STT signals
at producer emission. Never fill missing provenance from current room state
when the signal is handled. The room accepts a start/end only when the exact
binding is current, both routes and participants remain authorized, and the
end matches the active native turn reference. Unrelated global revisions do
not rotate the binding. The existing STS input queue receives captured epoch
and intervals only after this room check; queue admission is not proof of
completed provider delivery.

The current-origin side of this comparison belongs to the STT capability:
extend its bounded engine input-binding query with the selected native
allocation generation and scoped source-audio intervals. The room compares
that result with the signal's frozen generation/intervals before binding the
STS input epoch. The query must not mint an origin or infer one from a late
signal, and a non-selected or unready recognizer supplies no activity origin.
The current-origin query must also return no origin for a canceled native
allocation, even before the capability consumes its closure notification.
A ready prepared-policy replacement is a candidate, not the live origin:
its resource-scoped query returns no origin until adoption, after which the
adopted session may expose the same generation as the current binding.
This is a room-validation seam, not the separate ingress PCM cutover proof.

The STT ingress needs an acknowledged cutover, not merely queue clearing. It
must close admission, purge queued PCM and qualify each asynchronous delivery
with the allocation/input generation that admitted it. STT must reject an old
envelope before sending its audio to a new provider allocation; stale replies
must not unlock a new delivery credit. The cutover also needs a trustworthy
upstream received-before-open fence for pushes handled after reopening. The
existing `AudioFrame.received_at` is a possible seam only if every source
preserves its original timestamp; a source-issued generation is stronger. Both
policy-enforcer application orders need focused proof.

An enabling interval-proof slice now captures the ingress snapshot's STT,
audio-input and audio-output intervals in each asynchronous PCM envelope and
rejects a mismatch at capability delivery. A focused test first reproduced an
old envelope reaching a replacement provider, then proved old rejection and
fresh delivery. This does not yet qualify the native allocation generation,
fence pre-reopen frames, or coordinate hold; it must not be treated as the
completed cutover contract above.

The next producer-side slice preserves the native STT event's allocation
generation and turn reference plus the source's audio-input/output intervals
in each private signal at capability emission. This is immutable evidence for
later room comparison; it does not itself authorize external activity or bind
the selected STS epoch. The room must not infer a missing epoch from its state
when a delayed signal arrives.

Capability-emission stamping is not evidence of audio origin if a native event
waits across a policy change while its provider allocation remains alive. A
focused queued-native-end reproduction found exactly that on a recording-only
change: the old end acquired the new audio-input interval. Selected activity
STT now retires its provider on any scoped source audio-input/output interval
change, including recording-only changes, so a queued event from that old
allocation is rejected. This relies on successful session retirement and does
not solve hold/reopen, pre-cutoff PCM or native evidence first produced by a
provider that is allowed to survive another lifecycle boundary.

Hold, route loss, source replacement and transfer retire the room controller
association before a new interval opens. Under the current STT provider
contract, an allocation that consumed old or held audio must be retired and a
fresh allocation made ready before activity control is reopened. The provider
exposes no acknowledged discard/reset or frame-to-event origin correlation;
simply changing a room epoch or stamping a provider event at receipt cannot
classify evidence first surfaced after reopening. Transcript demand may keep
recognition available during denial, but that allocation cannot inherit fresh
activity authority; it must be replaced again before control resumes. A
failure to retire, start or reach readiness leaves control closed.

External mode sends the validated STT start and matching end through STS ingress.
Hybrid uses the STT pair for attribution but sends only its matching end;
provider-controlled mode sends neither. Loss of activity demand mid-turn
retires the pair without manufacturing a normal end. STS provider-side
external activity retirement is a separate requirement: hold must not synthesize
an end that prompts an old reply.

## Rejected alternatives

- Stamp the room's current STS epoch onto a delayed STT signal. This relabels
  already-emitted old evidence after hold/release.
- Stamp only the current STT transcript interval. Audio-only route changes can
  leave that interval unchanged.
- Rotate a generation while keeping the same provider session. A provider
  event first surfaced after reopen could still describe audio from before it.
- Clear only the ingress queue. One PCM envelope may already be in the STT
  capability mailbox and can otherwise reach a replacement provider.
- Send `:ended` on hold. Morse can treat it as a normal response-triggering end.

## Implications and verification

Retiring a native STT allocation costs reconnection latency and may truncate a
transcript. That is preferable to inheriting un-attributable old recognition;
avoiding it needs a new provider discard contract with acknowledged origin
isolation. Exact audio-input/output intervals are conservative: audio-input
also reflects recording policy, so a recording change may require a harmless
cutover even when the selected route is unchanged. Do not use global policy
revision as a substitute.

Focused reds must cover emitted old signals delayed across hold/release, old
provider evidence first produced afterward, audio-only revoke/regrant while
transcripts remain demanded, already-sent PCM crossing allocation replacement,
queued and pre-cutoff frames, both enforcer orders, unchanged-policy rebase,
failure-closed readiness, and compiled external/hybrid room response timing.
The first capability red (`selected activity STT resets its provider on
audio-route loss despite transcript demand`) failed 1/1 because no new provider
started after route denial; the scoped reset change now passes that test and
the adjacent 83-test group. This does not prove late-event or hold safety.
Scoped Astra xhigh code review found no concrete regression after 39 focused
tests and eight in-memory probes. It verified both route directions, unrelated
policy rebase, prepared adoption and ingress queue clearing; it did not close
the generation-qualified PCM, emitted-signal or hold gates.

Independent Astra xhigh source review identified the native event generation/
turn-reference seam and the already-sent PCM gap. It was read-only and did not
execute tests, so its broader design risks are not claimed as reproduced
runtime defects. The scoped capability red above is independently observed in
the local test run. See the milestone for implementation tasks and acceptance.
