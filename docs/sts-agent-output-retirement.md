# STS agent-output publication retirement

Status: room publication boundary implemented; hosted and full lifecycle acceptance
remain separate milestone gates.

## Decision

The capability forwards the channel's acknowledged semantic-event sequence with
each agent-output start. A queued legacy caller-end or opted-in response-start
retains that sequence until playback credit is granted. The resulting active
output carries the same sequence through transcript, completion and interruption
owner messages. The room accepts a start only from its current capability and
source, and only above its scalar retired-output watermark. A terminal message
must match the active association's sequence before it can publish or retire it.
Text also requires that exact match. Terminal retirement advances the scalar
watermark and drops the active private-to-public association. Capability
replacement resets the watermark together with the allocation binding; old
messages still fail the current-capability check.

This keeps room-owned public command/turn IDs private from provider references
without storing an ever-growing retired-ID set. The room may hold a later live
association while an earlier terminal advances the watermark. The capability
owns one credited output slot and sends its terminal before granting the next
queued output, so normal owner messages preserve publication order.

The watermark is **owner-message replay protection**, not upstream deduplication.
If a provider emits a new channel event with a fresh sequence but reuses a private
turn reference, the channel/provider protocol must decide whether that is a new
response. The room still requires exact sequence on late text and terminals so
old evidence cannot settle that new association. This decision does not prove
Google cross-origin cutover or hosted behavior.

Rejected alternatives: retaining the last N private IDs (an older delayed start
reopens after N turns); keeping every retired ID (unbounded); inferring order from
room publication sequence (it does not identify the original channel event); or
accepting an unqualified terminal for a reused private reference (old evidence
could complete the new public turn).

## Verification

The focused room regression first failed because a delayed start created another
`AgentSpeechStarted` after completion. After the change, the room boundary proves
25 sequential retirements without tombstone growth, stale-start rejection,
later-live-turn acceptance and stale text/terminal isolation when a private turn
reference is reused. Both queued legacy and opted-in starts retain their
accepted channel sequence through the busy output slot. The affected
capability/controller/room group passes 203
tests; the embedded room/lifecycle group passes 27. Independent read-only Astra
xhigh review found no concrete defect.
The first full call-engine run reported 1 failure in 1,412 tests (30 integration
exclusions): an unrelated Morse session readiness assertion timed out after
100 ms under suite load. Its isolated rerun passed; the full gate is not claimed
green on that run.
