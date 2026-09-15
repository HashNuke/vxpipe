# Repeated native transfers

The engine already verifies reception → billing → reception → billing with
stable participant identity, fresh activation and no greeting replay. Native
human recovery already retries a failed destination admission on the retained
caller. Extend the established AI sequence to actual WebRTC audio/transcripts
and recording, including monitor removal/re-entry during the second attempt.
This is acceptance of the existing contract; do not invent new human transfer
controls or require a production change if the scenario already passes.

Use the existing Morse STT/TTS, selective model constructor and controlled URL
wait fixture. Block each destination model independently, observe fresh wait
players and distinct attempts, retain caller/media/room services, and receive
cue before the first greeting or resumed speech. Require live caller transcripts
at both peers and spoken AI responses after every transfer. Read recorded PCM
and reject private waiting/cue frequencies. Fixture options select a short first
greeting and the already supported return destination; no runtime schema changes.

The first two fixture runs failed before transfer: the normal connection helper
acknowledges readiness and deliberately drains startup audio, so it discarded
the short initial greeting; an added readiness helper then consumed the sole
pending acknowledgement a second time. Use the existing connection's `ready? =
false` mode, send one client-ready request, release the blocked initial model,
and observe bot-ready without draining RTP. This corrects the acceptance fixture
without changing runtime startup behavior.

Check recording separately after each completed transfer, discarding only prior
conversation chunks after asserting they contain no wait/cue frequencies. Each
new conversation must then produce 700 Hz speech in recording and no private
250/1000 Hz audio. This avoids treating one early recorded utterance as proof of
recording across all three transfers.

The corrected startup reaches the first transfer. The native Morse reader then
interprets the tail of the 1000 Hz cue as a one-window Morse pulse and rejects its
timing. It previously ignored unsupported prefix frequencies but could accept a
transition window before actual Morse began. Begin decoding only when the first
coherent 700 Hz carrier window arrives; once decoding starts, retain all timing
and signal checks. This is receiver-side separation of the known cue prefix from
Morse speech, not a runtime decoder or playback change. The existing audio-order
check still requires receiving the connection cue first.

The first resumed-reply check initially answered an arbitrary queued model
request. A held source can have a continuation request already in the fixture
mailbox. Select the expected agent prompt and latest caller utterance before
responding, so each scripted response belongs to the active destination.

A later resumed Morse reply failed timing after the no-greeting check. That
check decoded and consumed RTP using a new Opus decoder instead of the peer's
persistent decoder, leaving the persistent state behind the packet stream.
Use the existing peer decoder when present; non-Morse tone fixtures retain their
previous behavior. Timing checks, emitted packets and runtime providers remain
unchanged. Re-run the complete three-transfer flow after this correction.

The complete native sequence now passes in 35.3 seconds. All three attempts have
fresh wait players and distinct IDs, and both agent re-entries replace their
model coordinator without replaying the configured greeting. The monitor leaves
and re-enters during the second model delay while the caller retains its player
and cursor. After each transfer, both peers receive the caller's transcript, the
monitor decodes caller speech, the caller decodes the active agent's reply, and
new recorded chunks contain speech without waits/cues. Caller connection/STT and
room service bindings remain equal to their original bindings.

After green, replace the duplicate readiness packet with the existing
`send_client_ready/1` helper, without using the draining readiness helper. Run the
original native Morse call, the repeated call and the expanded multi-listener
call together before the engine and umbrella gates. Full root verification must
use the original module, not only the temporary focused AST extraction.

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
