# Discarding obsolete conversational speech

## Decision

Output generations remain the privacy fence across a human handoff and recovery.
A conversational TTS request retains the generation captured when it was queued.
If its sink rejects audio with `:stale_output_generation`, the TTS capability
cancels that exact semantic request through the existing fence/cancellation
protocol. It waits for cancellation acceptance and the matching terminal before
starting another queued request. The capability, provider session, caller
connection and queued recovery requests remain available.

The owner receives an internal `:discarded` playback status after cancellation.
This settles one pending speech segment without recording delivered output or
adding its text to spoken history. It does not cancel the model or active tools.
Once text generation and all speech segments have settled, the existing
`AgentTurnCompleted` event marks the end of the turn; this event is not evidence
that every generated word was played. Actual speech history still requires
confirmed playback. Opening audio and private transfer briefings retain their
existing failure behavior; this recovery applies to conversational agent turns.

## Alternatives and implications

- Restamping old audio with the latest generation would bypass the handoff fence.
- Treating a stale generation as service unavailability incorrectly disconnects a
  recovered caller despite a healthy provider and output sink.
- A room-wide interruption would cancel unrelated model/tool work and discard
  queued recovery speech. Cancellation belongs to the obsolete request.
- A generic successful playback acknowledgement would falsely record unheard
  text as delivered and contaminate subsequent model context.

Queued requests are not relabelled or silently removed. Each retains its own
identity and generation, and receives its own cancellation if later rejected.
Other sink errors still follow the existing unavailable path. Provider usage
settles as cancelled, preserving the existing usage accounting boundary.

## Verification

Concurrent worktree acceptance exposed a late pre-handoff acknowledgement after
phone-transfer rollback. The output arbiter correctly rejected its old generation,
but TTS stopped with `:audio_output_failed`, ending the retained caller connection.

A deterministic capability regression holds sink delivery, queues a newer-generation
request, then returns the stale-generation rejection. Before the fix it reports
service unavailability and process termination. After the fix cancellation waits
for the provider terminal, the new request completes, and the old one never emits
completed playback. A room-owner regression verifies segment settlement, preserved
newer turns and unchanged spoken history, including generation still in progress.
The focused suites pass all 12 tests. Broader phone-transfer, umbrella and Lean
verification are recorded with the worktree milestone acceptance evidence.
