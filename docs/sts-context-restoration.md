# STS context restoration

Status: Google same-allocation resumption is implemented and covered by local
fake-socket tests; hosted verification remains pending. The user requested
resumption handles and clarified that callers must never hear historical
conversation replayed. Fresh-session history reconstruction remains only a
proposal, separate from restarting the agent-output speech recognizer.
It is not required for handle-based resumption or for completing this milestone.
A valid handle must not be supplemented with history replay. If a safe handle
cannot be used, the implemented behavior is explicit failure, not reconstruction.

## Provider support and current implementation

Google Live supports resuming a session with a server-issued handle, and
`clientContent.turns` can append ordered conversation history. For the pinned
Gemini 3.x profile, genuinely new text instead uses `realtimeInput.text`; appended
history is not a substitute for that input. This implementation sends neither
history nor a placeholder on reconnection. Setup acknowledgement must precede
further client messages. See the official
[session-management guide](https://ai.google.dev/gemini-api/docs/live-api/session-management)
and [Live API reference](https://ai.google.dev/api/live).

`Google.STSSession` requests handles on initial setup, retains the latest valid
resumable checkpoint privately, and clears it on a non-resumable update or new
accepted input. It can renew a connection or recover an idle connection loss
inside the same allocation. Loss of the provider process or the main capability's
speech allocation still ends that capability. There is no engine-owned context
snapshot/restore operation in `Speech.STSProvider`, and no fresh-session replay
in `Capability.SpeechToSpeech`.

The output-STT recovery fix only starts a clean recognizer for the next output
turn. It does not restore conversational-model context.

## Implemented handle handoff

`Google.STSResumption` owns one bounded attempt. An active reply may settle until
the earlier of Google's `goAway.timeLeft` deadline and the local connection
expiry. Once idle, connection/setup acknowledgement has a 5-second budget,
capped by that original deadline; it is not extended at internal stages.
An idle session missing a fresh handle also gets at most that 5-second budget.
Private reconnect-budget overrides must be positive integers at most 15
seconds. Periodic renewal and expiry timers are socket-qualified; late
timers/events from retired sockets are ignored.

The adapter waits for an idle input boundary, no outstanding tools, local
playback settlement, model completion and explicit interaction idle after
conversational work. Accepted PCM before onset invalidates old idle without
inventing a caller; observed model work and accepted tool results do likewise.
Missing status cannot inherit an earlier idle. `Speech.STSOutput` notifies the provider after successful
consumer settlement so generation completion alone cannot trigger reconnection.
When handoff starts, the old socket is retired through its owning supervisor,
without sending an additional audio-end command that would alter the checkpoint.
New input is rejected as `:busy` until the replacement acknowledges setup.

The new socket receives only setup with the private handle, then genuinely new
input. It receives **no historical audio, conversation-history input, tool replay,
or request to regenerate previous speech**. A rejected handle, missing safe
checkpoint, failed setup or exceeded deadline fails the allocation explicitly.
There is no fresh-session fallback. Unexpected loss with in-flight/uncertain
input, output or tools also fails closed rather than guessing what was accepted.

Local tests cover latest-handle selection, invalidation, revocation, idle loss,
setup acknowledgement, deferred playback settlement, silence/no historical
input during reconnection, stale socket events, private status, rejection and
timeout cleanup. Hosted continuity and interrupted-history semantics are still
unproven; the Google capability remains unadvertised.

Cross-direction checkpoint coverage is also not yet proven. The
[pinned SDK resumption update](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/types.py#L19197)
exposes a consumed-client-message index when transparent resumption is requested.
The current adapter does not request or account for that index. Arrival of a
new handle is not by itself proof that every accepted client message is included;
delayed earlier model-idle evidence needs the same audit. The milestone records
profile/numbering research, a deterministic crossing-direction reproduction and
successful fully covered renewal as open work before hosted no-loss acceptance.
This does not authorize replay, buffering historical audio, or a fresh fallback.

## Proposed fresh-session reconstruction boundary

Prefer native resumption when its identity, ordering and playback-history
semantics are proven. If fresh-session reconstruction is added, restore a
bounded, room-authorized snapshot before admitting new microphone input:

- Current instructions, authorized tool definitions and activation context.
- Settled caller turns and assistant text supported by the room's egress
  evidence; never treat all generated audio/text as delivered speech.
- Authorized tool-call/result records, including completed invocations whose
  speech was cancelled. Restoration must not execute a tool again.
- Current participant, source, policy revision and generation identities.

This is a proposed additional contract, not permission to silently restart now.
Text replay restores a conversation's semantic record, not necessarily its
original audio, prosody or provider-internal state. "Entire context" must have
an explicit size/compaction policy; arbitrary unbounded replay is not safe.
Existing transcript retention and privacy decisions still apply. This proposal
does not authorize additional durable storage or production Google selection.

## Rejected shortcuts and required verification

Do not resend history on top of a successfully resumed session: that risks
duplicating it. Do not replay raw microphone audio or pending tool operations
without acceptance evidence. Do not resume live input while restoration is
still in flight. Do not claim an interrupted generated reply was heard.

Before accepting fresh-session reconstruction, use a deterministic provider to verify
ordered restoration, a single response after readiness, no duplicate tool
side effects, stale-generation rejection, privacy revocation, bounded context,
restore timeout and cleanup. A hosted probe must then verify conversational
continuity and interrupted-history behavior, with separate authorization for
billable calls. None of those new restoration checks has passed yet.
