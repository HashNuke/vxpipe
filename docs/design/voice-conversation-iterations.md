# Voice conversation delivery review

Status: consolidated design/dependency review, 2026-11-16. The user's latest
voice-feature instruction selects one [combined milestone](../../labnotes/milestones/voice-agent-turns-and-listening.md)
with meaningful checkpoints. This supersedes the earlier recommendation to keep
three active feature milestone files. The later requested generic
[message-format milestone](../../labnotes/milestones/structured-agent-messages.md)
has its own four checkpoints, including the explicit idle tool. The index owns
overall implementation order.

## Decision

Keep one authoritative voice-feature checklist with six usable exits. The generic
message-format checklist owns its separate runtime protocol work. Specifications
retain detailed contracts and evidence; the two milestones have explicit boundary
ownership rather than duplicate implementation tasks.
Old milestone filenames remain as redirects and historical evidence, without
competing pending checklists.

| Checkpoint | Work combined into its useful outcome |
| --- | --- |
| A — ElevenLabs interrupted transcripts | Common timing plus playback cutoff, retained generation, spoken transcript and next-LLM context in a configured call. |
| B — Rime interrupted transcripts | A second integrated provider through the same contract, preserving estimated timing and language-dependent availability. |
| C — Structured interruption and modes | Consume the shared message protocol for semantic decisions without the classifier, endpoint/mode/purpose handling and ordered history in a call. |
| D — CPU filter in configured calls | Artifact parity/build, thread-bounded shared serving, participant filtering, language/default settings and semantic fallback in the working call. |
| E — Transcript-driven listening cues | Early replay/listening experiment, accepted selector, prepared voice bank, settings and real audible cues through C's shared boundary. |
| F — Telephone calls and language coverage | Combined behavior across declared transports/languages/providers and CPU profiles, with measured ordinary-response latency. |

A provider adapter, worker pool or mode flag alone is not a completed checkpoint.
B is useful because it enables the complete behavior for an additional provider,
not just another wire decoder. F expands the runnable configuration to telephone
and declared additional profiles; it is not merely a root-test bucket.

## Shared contracts and dependencies

TTS timing, spoken transcript and LLM history ship together in A. Showing only
`x y` in an interface while keeping `x y z` as previously spoken model context
would leave the core requirement unfinished. Keep generated evidence and privacy
filtering in the same slice. B reuses the contract with Rime's estimate quality.

The message milestone owns the basic speaker/listener lifecycle. Voice C adds
output-purpose and cue-window policy to that shared state. E produces real
listening cues through that boundary; it must not create another mode machine
or history writer. Generation alone is not acoustic overlap. If A is unavailable,
C still needs the common coarse unknown-delivery history projection.

The [structured-message contract](structured-agent-messages.md) now has a
[dedicated implementation milestone](../../labnotes/milestones/structured-agent-messages.md).
Its A delivers attributed content, basic modes and coarse history, B retains native calls and
responses without extra pending snapshots, and C enables validated final replies.
Voice A depends on message A's history boundary; voice C depends on message C's configured protocol and D's native idle action. The message milestone does not depend on precise timing,
the classifier, new overlap policy or cues, so this is not a dependency cycle.

The format catalog adds runtime-owned `agent_mode` on participant and proposed
platform input, frozen at initial input admission, and one common agent_mode/message
response for ordinary dialogue and interruption. Existing tool
results/completion observations retain their original format without mode.
Playback/classifier/overlap diagnostics remain internal; only supported spoken
text reaches history. No delivery/correction event is sent to the LLM. Stable
platform protocol instructions supplement authored instructions, and the compactor
retains specified conversational facts. Mode alone is not authority or overlap.

Original native tool-call messages, genuine submission responses and final
outcomes remain in history. Only additional pending-status inventories disappear.
The message milestone owns generic prefix/cache, provider/tool, migration and
structured-stream validation checks. Voice A/B add precise delivered-word evidence;
voice C adds actual interruption authority; voice F tests the integrated language/
transport behavior and retains the one-second target. The extracted work has
four configured-agent exits, including timed idle, not an envelope-only completion.

D depends on C's semantic fallback for its selected profile. Native binding,
artifact and worker research can happen earlier, but activation waits for a
bounded end-to-end classifier path. No ONNX blocker should prevent A/B or E.

E's experiment can start immediately on existing speech/replay foundations. Its
runtime activation requires C's mode/purpose contract and a passing listening
quality gate; it does not require D, outgoing TTS alignment or default local VAD.
Failed timing experiments leave E open rather than producing an inert feature
that never emits useful cues. STT timing and TTS timing are separate contracts.

The index places the message-format milestone before the voice milestone. The
conservative order within voice remains A, B, C, D, E, F. Its
explicit dependencies allow E's experiment early and its runtime work after C
even if D is unfinished. First-profile checkpoints do not claim all-provider,
all-language or one-second acceptance; F retains those declared broader gates.

Classifier artifact download/verification and offline-image smoke belong to D.
General publishing, installation onboarding and distribution stay in the existing
delivery milestone. Never commit model weights/tokenizers/history to application
Git or download artifacts during startup/call admission. The Models-tab classifier
disable control remains a deferred UI task to create at implementation promotion,
with default-on/explicit-off runtime preferences included in D.

## Review and rejected alternatives

Reviewed the three specifications, prior milestone task lists and already
inspected runtime boundaries: unconditional onset interruption, segment-level
spoken history, mutable model conversation, conditional archival retention,
discarded timing metadata and scoped playback settlement.

The consolidation removes duplicate task ownership. The combined milestone's
coverage table maps every former checkpoint and every specification area into
A–F or the explicitly extracted message-format owner. It retains the completed
Scribe wait-removal checkpoint at its original
link and keeps all new implementation boxes unchecked.

Rejected a single all-or-nothing implementation exit because classifier serving
and cue-quality uncertainty would block useful transcript and semantic changes.
Also rejected separate infrastructure-only checkpoints and duplicate active
checklists across specs. One milestone provides scope/accountability; its runnable
checkpoint exits provide small independently reviewable delivery steps.

Earlier Astra xhigh review covered the combined draft against its source
specifications and saved pre-consolidation task lists. The dedicated message
milestone and latest tool-call clarification received a fresh Astra xhigh
extraction review with no material findings. Ownership, configured exits and
acyclic dependencies were confirmed. The milestones and labnotes record review
findings separately from runtime acceptance.
No implementation, live-provider or deployment claim follows from this review.

The latest user scope defers call_state_changed (existing variable context remains),
renames the model event idle_timeout, and adds common listener/message cue intent.
Message A owns DB/publication/JS projections; D owns explicit idle, optional speaker
acknowledgment, a timer starting after settled acknowledgment, and one timeout or
fresh-input resumption. This resolves ignore-versus-stop without interrupt_agent.
