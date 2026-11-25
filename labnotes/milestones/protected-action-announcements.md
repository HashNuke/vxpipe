# Protected announcements before hangup and transfer

## Runnable outcome

A text agent with a configured TTS voice can include one short optional `announcement` on a platform hangup or allowlisted participant transfer. The caller hears it on the existing call using the active voice. Caller input cannot interrupt the announcement or restart the conversation during carrier drain. The action proceeds as soon as playback drains, or after a bounded playback failure. Omitting the argument preserves immediate action.

## Prerequisites and design review

This builds on [agent transfers](agent-transfers.md), [transfer readiness and wait sounds](transfer-readiness-and-wait-sounds.md) and the playback and barge-in contracts in [voice agent turns](voice-agent-turns-and-listening.md). The preceding Astra and Opus design reviews identified two ordering constraints. Destination preparation holds the caller output and must follow announcement delivery. The gateway reports local completion before its remote drain acknowledgement. Native speech agents require their own repeatable fixed-speech operation before advertising this parameter.

The room owns a single reservation for the current source, caller output and action. TTS owns synthesis. The sink owns drain. The tool worker never drives audio. The deadline and late evidence must not duplicate actions. Disconnect and administrative hangup retain priority. The transfer attempt retains its own preparation budget.

The [architecture decision](../../docs/design/protected-action-announcements.md) records process ownership and failure behavior. The [checkpoint notes](../20261125-1146-protected-action-announcements.md) record red tests, review and verification.

## Implementation and acceptance

- [x] Project a bounded optional parameter only for supported agents and accept both tools through their normal invocation path.
- [x] Protect caller input and competing output until playback and sink drain settle. Exercise both actions with a delayed drain and caller intervention.
- [x] Handle playback failure, timeout, stale evidence and room termination. Verify ordinary no-announcement and native tool paths.
- [x] Run focused tests, umbrella checks and Lean replay. Record verification in the checkpoint notes.

For a handset listening check, invoke each tool with a short sentence, speak over the last word and confirm the call ends or transfers only once. Record handset evidence separately from deterministic media tests.
