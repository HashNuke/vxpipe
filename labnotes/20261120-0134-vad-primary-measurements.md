# VAD primary measurements

## Decision and evidence

The user clarified two primary metrics: acoustic end to STT turn-end receipt,
and acoustic onset during agent playback to acknowledged playback stop. CPU cost
is advisory for this optional benchmark. Dispatch and first audio are supplementary.

Read-only inspection finds TurnTiming already computes speech_end_to_provider_end,
but its allowed landmarks and metrics contain neither acoustic onset nor playback
stop. ResponseTiming observes only first text and first audio. The prior timing
acceptance audit proves cancellation and suppression of late output, not a measured
barge-in stop. Therefore the milestone now explicitly tracks this missing vertical
slice rather than treating prior interruption tests as sufficient evidence.

A barge-in segment must link to the output already playing, potentially from the
previous human turn. Adding a stop field to the next response alone would measure
the wrong interaction. Keep clock/source/output identity and unavailable reasons.
The WebRTC AudioEgress interrupt handler clears its local queue and returns played
milliseconds without a remote-browser playback acknowledgement. Its timestamp can
prove server egress stop, not remote audible stop. The contract explicitly requires
this provenance/uncertainty rather than overstating the endpoint.
No runtime change or test success is claimed by this documentation checkpoint.
Existing uncommitted egress harness work is preserved separately and is incomplete.

## Verification

Independent GPT-6 Astra xhigh design review found the missing distinction between
server queue-clear acknowledgement and remote audible stop, reproduced from the
WebRTC AudioEgress interrupt handler. The clarification above resolves it; re-review
returned no findings. Documentation diff checks pass. No live providers or production
service were invoked. This is design review, not implementation acceptance.
