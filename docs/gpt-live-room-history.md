# Room-published GPT-Live reseed history

## Decision

The room is the authority for transcript publication. A speech capability
forwards caller and settled agent text as evidence, but does not append that
text to a history-reseed provider yet. After the room accepts a final caller
transcription or played agent text, the transcript publisher reports the
router-approved recipients. The room acknowledges publication only when the
virtual agent route or human delivery is approved. The capability, as the
allocation's consumer, then calls `Session.append_history/2`. The capability accepts the
acknowledgment only from its owning room process and only for a provider whose
descriptor declares `continuity: :history_reseed`.

Before either provider snapshots history after a lost session, it asks the
speech channel to place a barrier in the capability mailbox. The capability
first processes every earlier room acknowledgment. For a room-owned call, it
then places a barrier in the room mailbox. The room replies after every earlier
publication handler has finished and only while that capability remains
current. The capability processes any acknowledgments sent by those handlers
before releasing the provider. The GPT-Live reconnect deadline includes this
wait; the scripted Morse close has a bounded wait as well. If the room or
capability cannot respond, reseed fails instead of starting with a stale seed.

The agent is a room capability rather than a physical connection. For caller
transcripts, the publisher includes that virtual agent as a route candidate
and requires the router to approve the caller-to-agent route. The recipient
set still drives network delivery only to real connections. Agent text
requires the human connection in the router's delivered set.

This keeps a stale caller epoch, hold, policy revision, agent turn, or a
transcript suppressed by the router from entering the replacement session's
seed. It also covers final text supplied by a `:turn_ended` event after an
inferred caller turn. The provider's bounded
history and its one-reseed behavior are unchanged.

## Rejected alternatives

- Appending when the capability forwards evidence can seed text that the room
  later rejects. A local transcript-route check cannot decide the room's
  current epoch, hold, connection, and publication state.
- Giving the room direct access to the provider allocation would bypass the
  speech channel's consumer ownership rule.
- A synchronous room-to-capability call would make publication wait on the
  provider session, tying room event handling to a network-backed process.
  Room publication and the reseed barriers use ordered process messages.

## Snapshot boundary and verification

The seed includes every transcript whose room publication handler finished
before the room processes the barrier. This includes publication work already
in progress when the provider detects the disconnect. Later publications are
not part of that replacement's seed. A subsequent replacement is not attempted
by this provider.

Focused tests first failed because the capability had already appended
forwarded caller and agent text and the room sent no acknowledgments. A
second red run found that the room acknowledged text suppressed by a failed
router. The updated tests prove that the capability's history is empty before
room acknowledgment, that delivered final caller and agent publications emit
one, and that a held caller's rejected final text or a router-suppressed
transcript emits none. A routed-room test proves that an authorized virtual
agent still receives a caller history acknowledgment. The publisher reports
the route-approved recipient set, including an empty set on policy-revision
mismatch. A suspended-capability test first failed because GPT-Live opened a
replacement before consuming an already queued room acknowledgment. A second
red test showed it also opened before the room completed its publication
barrier. Both now pass, along with the Morse scripted-close suite and a room
test that acknowledges only the current capability. Test commands and root
gate results are recorded in the milestone's checkpoint E response and linked
labnotes.
