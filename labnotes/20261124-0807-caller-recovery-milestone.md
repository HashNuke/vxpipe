# Caller recovery milestone planning

The November 24 QA call established the failure boundary: interruption succeeded, the final transcript never arrived, STT failed and the caller media detached, leaving the phone leg marked active in storage. Available evidence did not identify the underlying provider failure. Prioritize the surviving carrier leg before introducing in-room retries. The scope is an established inbound Telnyx/Scribe caller; the adjacent voice milestone owns interruption classification.

Added the ownership decision, four implementation checkpoints, and an unchecked milestone following passive diagnostics and before pending voice policy. Existing code maps STT loss to a connection-unavailable notification and media shutdown. Telnyx VoiceClient supports dial, answer and hangup. Provider playback, transfer ownership and exact webhook evidence need explicit interoperability gates.

## Failed QA trial, November 24 UTC

At 07:52:27.148 the room recorded the interruption and caller turn start. No matching final transcript or accepted input was present. At 07:52:37.609 the runtime logged STT session failure and the phone media session stopped with media unavailable. At 07:54:25 the database still showed a running call and active leg. The caller reported silence. These observations establish the local failure and stored status; remote carrier status, handset playout timing and the originating Scribe fault were unverified. The earlier comparison call is recorded separately in the [baseline](20261124-0743-caller-barge-in.md).

## Independent design review

GPT-6 Astra at xhigh requested changes before implementation. It accepted index placement and prerequisite order. The revision specifies command-worker versus owner/node loss, fenced carrier ownership across room teardown, a bounded storage-outage exit, operational acoustic transitions, explicit episode and transfer deadlines, and caller-only cue routing. Each finding has a corresponding failure test in checkpoints A–C. Updated index counts and separated the failed trial from comparison measurements. This review records specification work; all implementation and live gates remain open.

Verification counted 69 ordered entries (54 complete, 15 incomplete), checked relative links and the incident anchor, and confirmed all 24 implementation tasks remain open.
