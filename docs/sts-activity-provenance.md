# STT-owned activity provenance for room STS

Status: reviewed design candidate, not implemented room control. The initial
selected-STT demand checkpoint is committed; a focused red reproduced the
remaining transcript-demand/audio-route provider-retention gap. The provider
reset change in the worktree is only an enabling slice. Ingress cutover,
allocation binding, hold/release and room acceptance remain open.

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
