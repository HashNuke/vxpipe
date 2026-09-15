# Listener arrival after adoption

The previous turn made progress: `252e4b7` publishes the waiting audience before
blocked destination construction returns. The native monitor hears waiting
immediately; 52 focused transfer checks and all five root gates pass with 1,435
tests, zero failures and 16 exclusions. Eight compound checkpoint tasks remain.

Extend the existing native multi-listener call through one final boundary.
Pause the human destination's adoption control after authoritative policy has
changed, admit another planned monitor, then resume adoption while withholding
that monitor's WebRTC attachment. The room must remain preparing and resume
waiting during the membership-to-attachment gap, then cue every current listener
before conversation. This directly exercises the adopted preparation branch,
which currently uses `Preparation.run` without the pre-adoption missing-media
retry. Run that boundary red before changing the runtime.

The first native assertion watched the private destination progress channel after
adoption. Temporary stage/boolean-only diagnostics show the participant is
present and the new adopted branch repeatedly waits for its missing connection;
that assertion does not observe the caller's ongoing transfer status. Remove
all diagnostics and assert the public caller RTVI `preparing/media_connection`
progress instead. Re-run the corrected fixture against the previous committed
handoff implementation before accepting the red/green evidence.

The proposed runtime change retains the updated live bindings and wait map when
the adopted resource query reports the specific missing-media-connection error.
It reuses the existing bounded connection-wait helper under the original deadline.
Other failures and any failure after actual conversation release retain their
existing behavior. No replacement policy application or second promotion occurs.

Source review identifies the exact progress contract: private destination
progress requires its transfer admission, and public progress goes to the
connection that requested the transfer. This multi-listener fixture requests
from the third human, not the entry caller. Assert that peer's existing `media`
blocker. The internal `media_connection` kind must be normalized to `media`;
otherwise the public progress allowlist filters it out. The shared connection
wait helper now reports the existing public kind without adding a field.

The fully corrected native fixture fails against the committed runtime in 18.0
seconds while awaiting the requesting peer's media blocker. With the retry it
reaches attachment. One run then closed with `room_changed`; the safe handoff
result in the existing failure log identifies the changed inventory. The adopted
query now retries the same known stale-candidate/room-change errors as initial
preparation while all conversation gates are still held. This does not retry
errors after release begins.

A diagnostic run passed, and a subsequent clean run reached conversation but
missed its ordered audio assertion. No packet stream, assertion or deadline was
relaxed. With the adopted inventory refresh in place, the final clean native
case passes in 16.9 seconds: the new monitor joins after policy adoption, the
existing audience hears renewed waiting during its attachment gap, then every
current connection receives cue-ordered conversation with retained room/media
bindings. Continue the repeated-transfer acceptance before the full checkpoint
verification.

The combined three-case native run finished with two passes and one failure in
the multi-listener final audio-order check (66.2 seconds total). One audience
assertion ended in waiting without observing conversation. Do not close the slice
on the earlier isolated pass. Identify the affected peer and received phase
transitions using temporary, synthetic-ID-only diagnostics; preserve the packet
stream, cue requirement and original protocol deadlines. The preceding status
turn verified this terminal result and changed the next action to investigation.

Temporary diagnostics identify each native peer and record only synthetic
connection IDs, RTP sequence numbers and detected phase transitions. The
isolated multi-listener call passes (23.5 seconds), then all three native cases
pass together (64.8 seconds). All seven audience connections and the human
destination receive ordered cues and conversation, including renewed waits
after policy changes. The diagnostics exist only in temporary extracted copies;
no production or repository test assertion was changed for these runs. The
earlier failure has not been causally explained. Continue focused engine and
full original-module regression before accepting this checkpoint.

Final checkpoint verification passes: all 61 focused engine transfer/player
checks and all five umbrella gates. The full original suite has 1,436 tests,
zero failures and 16 integration exclusions, including 653 engine and 411
Gateway tests, with seed 235296, concurrency four, module preloading and
serialized test-file compilation. The earlier native ordering failure does not
recur in this run; its cause remains unproven. No runtime deadline, packet stream
or ordering assertion was relaxed. No temporary diagnostic prints remain in
repository code.

Reviewed the compound listener tasks against the owning player, inventory,
barrier, collector, human/agent transfer, output and diagnostic tests. Existing
native human recovery retries a later admission on the retained caller; native
release-loss cases complement engine cancellation and partial-release checks.
The milestone now accepts changing/multiple listeners and maps the common
requirements to this evidence. Three tasks remain: live carrier audibility and
two final audit gates, which cannot close without required external evidence.
Presence-only inspection confirms carrier configuration names are absent from
both the process environment and local environment files; no values were logged
and no provider call was placed. Commit this coherent slice with its docs.
