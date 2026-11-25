# Playback before hangup and transfer

A text agent with a dedicated TTS capability can supply one optional announcement of up to 240 characters when requesting hangup or transfer. The tool executor submits the request to the room. An accepted submission ends the current model round silently. The invocation registry also defers model continuations from sibling tools until the action settles. A failed transfer releases that hold so the source agent can resume.

The room reserves the action and holds caller input, ordinary agent output and idle prompts. It sends a purpose-tagged speech request to the active TTS capability with the caller's current sink and output generation. TTS retains ownership of its synthesis session. A separate connection for announcements would introduce a second owner for voice settings, ordering and cancellation.

After local playback finishes, the room waits for the sink's drain acknowledgement. A renderer can finish while the carrier still has buffered audio. Only confirmed drain marks the announcement delivered and records it in an enabled archive according to the call's retention policy. Destination preparation starts after this point because its media hold can silence the caller's connection. A receiving agent starts a fresh conversation.

The room allows 20 seconds for synthesis, playback and drain combined. A failed renderer, a drain error or expiry advances the still-authorized action. Caller disconnection or replacement invalidates the original output binding. Administrative and remote hangup can end the room during playback. Hangup remains reserved through tool-result settlement, with a one-second fallback if settlement is lost.

The capability-specific schema lets a native speech agent retain its ordinary hangup and transfer contracts until it has a fixed-utterance playback operation. See the [milestone and verification record](../../labnotes/milestones/protected-action-announcements.md).
