# Agent backchannel responses

Status: deferred by user request, 2026-11-17; no implementation or listening
prototype has run. The user shelved this work after discussing the unresolved
timing of transcript-driven opportunities. The proposal below is retained for
future reconsideration; neither prototyping nor runtime activation is active. The [combined milestone](../../labnotes/milestones/voice-agent-turns-and-listening.md)
owns delivery and acceptance. This concerns acknowledgments the agent produces
while listening. The [barge-in classifier proposal](barge-in-classifier.md)
concerns human input during the agent's main response; its classifier predicts
a different behavior and is not an agent-cue timing model.

## Decision and limits

Prototype transcript-driven listening cues for LLM-plus-TTS agents with local
VAD disabled. Use fresh, authorized interim transcripts to select an occasional
brief acknowledgment, with bounded timing, frequency and output admission.
Use the common agent_mode=listener/message result for semantic cue candidates.
Prepare a small reviewed phrase bank as a cache/content baseline and compare
bounded on-demand TTS for accepted cue text. A cue is still subject to timing,
content and language admission; the returned mode does not bypass those gates.

All tasks belong to the combined milestone: C owns shared modes/purpose, E owns
the experiment plus accepted selector, prepared playback and configured audible
call, and F owns wider telephone/language coverage. E's experiment may start
independently, but is not a complete runtime checkpoint on its own. CPU classifier
serving and outgoing word alignment are not prerequisites. The
[delivery review](voice-conversation-iterations.md) records this grouping.

Use **listener mode** and **speaker mode**, as selected by the user. Listener
mode may include audible backchannel cues. Speech by the agent does not imply
that the human should stop: human audio and transcription continue in both modes.
A cue must not end the human turn, make its continuation count as a fresh
interruption, or create a normal LLM response.

Transcript arrival does not establish acoustic timing. ASR can buffer, revise,
batch or stall. A gap between transcript messages does not prove silence; a
punctuation mark is not an endpoint. The default path must work without adding a local VAD or
requiring acoustic pause/prosody signals. Providers may use their own internal
VAD for recognition/endpointing, as Scribe already does. We cannot infer that
the entire upstream system is acoustically blind.

The prototype must establish useful coverage as well as appropriate timing.
Always declining to play is safe but does not solve the awkward-silence problem.
If fresh transcripts cannot support good audible timing, record that result and
keep the feature experimental. Adding required VAD would be a separate scope
decision, not an invisible implementation shortcut.

## Research: what the supplied sources actually implement

Sources inspected on 2026-11-16. These are descriptions of published mechanisms,
not measurements made against Vxpipe or proof of their production quality.

| Source | Observed approach | Implication for Vxpipe |
| --- | --- | --- |
| [Rime guide](https://www.rime.ai/resources/what-is-back-channeling-in-conversational-ai-a-plain-english-guide) | Describes choosing timing from prosody, pauses and clause cues, then producing a short acknowledgment with conversational TTS. Stresses that late feedback sounds misplaced. | Supports testing voice quality and end-to-end timing. It does not demonstrate a transcript-only scheduler or justify treating an ASR update gap as silence. |
| [Pipecat extension documentation](https://docs.pipecat.ai/api-reference/server/extensions/pipecat-backchannel) | Community-maintained and not officially tested/supported by Pipecat. Uses its own VAD and turn analyzer to find incomplete-turn pauses; caches clips made by the configured TTS and excludes cues from ordinary LLM context. | Reuse the prepared-audio idea. Its pause detector is incompatible with requiring no local VAD. |
| [NVIDIA turn-taking documentation](https://docs.nvidia.com/nemo/labs-voice-agent/about/core-concepts/speech-pipeline/turn-taking-backchannels#turn-taking-mode) | Nightly documentation describes VAD plus ASR boundaries, and suppresses recognized human acknowledgment phrases while the bot speaks. | This is mainly incoming backchannel suppression, not outgoing listening-cue generation. Its vocabulary list and endpoint rules do not solve this milestone. |
| [Inworld back-channel API](https://docs.inworld.ai/realtime/usage/back-channel) | Evaluates partial transcripts using an LLM or rule selector, with a phrase bank, spacing/caps and a combined decision/TTS deadline. `require_pause` defaults false; output has separate cue identities. | Closest reference for this proposal. Its API supports not requiring a pause signal, but does not establish that its backend has no VAD or that transcripts alone guarantee timing. |

Inworld documents 800 ms evaluation intervals, a 4-second minimum gap, at most
three cues per turn, a 1.5-second deadline, and gain 0.6. It also warns that
ducking all playback during human speech can hide cues. These are reference
settings, not Vxpipe defaults. [API details](https://docs.inworld.ai/realtime/usage/back-channel).

The Pipecat extension's [own README](https://github.com/maisterr/pipecat-backchannel)
limits the current selector/clips to English and pause-triggered behavior. It
recommends disabling feedback in phases such as number dictation, where a cue
can sound like confirmation. Its cache and cadence are not a multilingual
semantic policy. Rime's [Mist v2 announcement](https://www.rime.ai/resources/introducing-mist-v2)
supports that model's synthesis of conversational affirmations; actual configured
voices still need listening tests.

The underlying [Ward research overview](https://www.cs.utep.edu/nigel/bc/)
describes prosodic opportunities and language-dependent timing/frequency. It is
evidence against a universal silence duration or an English cue bank for every
language. The prototype should be judged with native listeners and real ASR,
not only fluent-looking text.

## Existing Vxpipe boundaries

At inspected baseline `64a4626a`, the completed
[transcript-start milestone](../../labnotes/milestones/transcript-start-and-optional-vad.md)
defaults local VAD off. The first nonempty transcript starts the human turn;
provider correlation and endpoints remain separate. The
[input handler](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority/input_turns.ex)
stores replacement transcripts, rejects stale turn identities and dispatches
completed caller input. It does not yet own a listening-cue policy.

The [STT signal](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/provider/speech_to_text/signal.ex)
does not supply a general stable-prefix contract, acoustic-pause timestamp,
per-word timing or detected language. Keep receive time distinct from any
provider/audio-clock evidence. Final-only transcription offers no reliable
mid-turn opportunity and should skip cues rather than create synthetic partials.

The [TTS request](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/text_to_speech_request.ex)
already distinguishes agent-turn, opening and transfer-briefing purposes, but
has no backchannel purpose. [Playback routing](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority/playback.ex)
falls through to normal agent-output handling after transfer/opening checks.
Adding cues therefore needs explicit purpose-aware routing and settlement.

[Opening-audio preparation](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/opening_audio/text_preparation.ex)
and its bounded tenant-aware cache demonstrate synthesis-to-cache; the
[wait-sound player](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/wait_sounds/player.ex)
demonstrates paced frames and acknowledged sink cancellation. They have opening/
transfer semantics. Reuse or extract cohesive playback primitives with tests;
do not label a listening cue as a transfer or opening operation.

## Listener mode, speaker mode and output purpose

Mode belongs to an exact voice-agent activation. The room validates changes
proposed by its participant policy; ordinary audio callbacks cannot switch it.

| Agent mode | Output | Input handling |
| --- | --- | --- |
| Listener | None | Accumulate the active human transcript; evaluate eligible cue opportunities. |
| Listener | Backchannel cue | Continue that same human turn; cue-only overlap does not invoke the barge-in classifier or interruption LLM. |
| Speaker | Main response | Continue receiving human input; apply the existing selected interruption policy when its overlap conditions hold. |

Mode and physical playback are distinct. Enter speaker mode when an ordinary
speaker result is validated and admitted, including its subsequent TTS preparation;
remain listener while evaluating a response decision. Do not wait for first audio
or claim generated/queued audio was heard. Enter
listener mode after that response settles or an accepted interruption cancels
it. Failure or a valid no-response outcome must also settle a pending response
that never produced audio. A main response ending while a human candidate is
pending does not erase that candidate's original overlap evidence. Preserve the barge-in proposal's
correlation/decision rules for that real main-response overlap.

### Turn completion and response admission

For an agent listening to its authorized human target, a confirmed endpoint
immediately closes that turn's cue opportunities and cancels its queued/active
cue. Evaluate the ordinary response without switching mode merely because a request
starts. Switch to speaker when the main speaker/message result is validated and
admitted. No extra silence timer or first-audio wait is needed; cue cancellation
must settle before main audio is released.

| Event | Mode and cue behavior |
| --- | --- |
| Human turn remains open | Stay in listener mode; consider eligible listening cues. |
| Confirmed endpoint | Close the cue window and evaluate the response while listening. A validated/admitted speaker/message result enters speaker mode before TTS. |
| Confirmed endpoint with no response admitted yet, or a valid no-response decision | Close cues; remain in listener mode while there is no main response. Listener mode alone does not authorize cues on a closed turn. |
| Eager/provisional endpoint | Suspend cue opportunities; optional speculative preparation is not main-response admission. Stay in listener mode until confirmed admission. |
| Provider resumes that provisional turn | Discard its speculative response/cue decisions and resume listening to that same turn; require fresh evidence for new cues. |
| Main response finishes, is cancelled, or fails before audio | Settle its exact response generation and return to listener mode. A stale completion cannot change the mode of a newer response. |

These transitions are scoped to the selected human turn and agent activation.
An unrelated participant's endpoint does not switch this agent. An ignored human
backchannel during an existing main response does not create a new response or
reset its mode. If the human starts again while the agent is preparing an answer,
ordinary input/generation supersession rules apply; speaker mode by itself is
not evidence of audible overlap and cannot activate the barge-in classifier.

Flux distinguishes [eager predictions, resumed turns and confirmed endpoints](https://developers.deepgram.com/docs/flux/voice-agent-eager-eot).
Keep that distinction in the policy. Optional speculative generation is a later
latency optimization, not a prerequisite for listening cues or permission to
play an answer before confirmed admission.

### Output identity

Each output carries an explicit purpose, unique output identity and generation.
Suggested new purpose: `:agent_backchannel`, alongside existing `:agent_turn`.
Keep the actual audio visibility scope (`conversation`, `private`, `mixed`)
separate from conversational purpose. This may require purpose metadata at sink/
client boundaries or an authoritative output lookup; it is not present end to end
today. Infer neither listener mode nor interruption eligibility just from “some
agent audio is playing.”

Cue start/completion never toggles mode. Normal response admission invalidates
queued cue decisions, cancels an active cue and waits for its bounded sink
acknowledgment before releasing main-response audio. Old cue completions match
only their own output and cannot reset speaker mode or discard a new answer.
An explicit idle operation cancels cue opportunities, permits its optional
associated speaker acknowledgment, then returns to listener for the quiet interval.
No cues are emitted during that interval; fresh human resumption retires the idle
hold. A failed cue cancellation must not overlap two outputs or fail the call; use
the established sink-failure/recovery boundary and measure any resulting delay.

The new purpose is not an input-muting exemption. Continue STT, preserve every
permitted human transcript and process the human's real completed turn normally.
If a human says “stop doing that,” the request must survive to ordinary handling.
The cue does not itself schedule a main LLM response or reset idle_timeout timers
as if the human had spoken. Multiple agents or ambiguous concurrent human
speakers default to skipping cues until a unique authorized listening target is
known; do not let every agent acknowledge the same turn.

## Can transcripts identify short pauses?

Text can predict that an acknowledgment fits the meaning of an unfinished turn.
It cannot, by itself, establish that the human is silent now. A gap between
transcript messages could be a pause, decoder buffering, unchanged text or
network delay. A clause boundary is a semantic opportunity, not an audio clock.
Allow a transcript-gap estimator as a labelled prototype hypothesis, evaluated
against recorded audio; never promote that estimate to a confirmed pause or
turn endpoint. Useful cues may overlap speech, as the Inworld API allows.

Separate **cue selection** (whether and what to acknowledge) from **cue timing**
(whether that candidate is still appropriate to play now). Compare these timing
inputs without requiring local VAD:

| Available evidence | Permitted use and limitation |
| --- | --- |
| Fresh text, clause context and transcript arrival cadence | Predict an opportunity, allow brief overlap or skip. Do not promise placement inside a silence. |
| Provider word timestamps plus advancing processed-audio windows | Investigate a gap since the latest recognized word, with source-clock mapping, revisions and bounded ASR/transport lag. A historical gap may already be over; unrecognized speech may still be present. |
| Explicit provider short-pause/speech-activity signal, if a profile exposes one | Optionally gate a cue independently of endpointing. Validate freshness and speech-resume behavior for that provider/model. Do not assume every provider offers it. |

For a timestamp experiment, compare the latest processed-audio position with
the last recognized word's end on the same stream clock, then check how far
behind live input that evidence is. Subtracting a provider timestamp from the
local wall clock, or using the amount of audio merely sent to the provider,
does not establish current silence. Recheck freshness and source identity at
audio admission; resumed speech invalidates a pause-specific candidate, while
a separately evaluated overlap-allowed cue can still be appropriate.

Provider findings at the inspected baseline:

- [Flux's API](https://developers.deepgram.com/reference/speech-to-text/listen-flux)
  shows audio-window positions and word start/end times. The local
  [Flux decoder](../../apps/vxpipe_call_engine/lib/vxpipe/providers/deepgram/flux.ex)
  accepts `words` but discards them, retaining window duration rather than its
  positions. Prototype preserving this optional evidence; verify actual interim
  availability, revision behavior and cadence on the deployed model. The API
  example alone does not prove a timely mid-turn pause signal.
- [Scribe's documented keepalives](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies#keeping-the-connection-alive-during-silence)
  are empty or repeated partials driven by processed audio, with roughly
  one-second processing cadence. They are different from receiving no message.
  The current [Scribe configuration](../../apps/vxpipe_call_engine/lib/vxpipe/providers/elevenlabs/scribe.ex)
  uses `scribe_v2_realtime`; its
  [continuous adapter](../../apps/vxpipe_call_engine/lib/vxpipe/providers/elevenlabs/continuous_stt.ex)
  uses an empty partial after committed text to settle the turn. That event is
  not an earlier cue window. The current generic text events carry no word
  timings. Revalidate model-specific capabilities; newer documentation also
  describes Scribe v3 features that this integration does not select.
- [Deepgram Nova's UtteranceEnd](https://developers.deepgram.com/docs/utterance-end)
  detects word gaps from finalized/interim transcripts, but its documented
  typical one-second interim cadence limits shorter triggers. It is a different
  API from the current Flux integration; do not assume its settings/events are
  available here or that a word gap means the human's thought is complete.

Do not lower the ordinary turn endpoint threshold just to obtain cue timing,
force transcript commits for cues, or make a cue timer end the human turn. A
short pause and a completed conversational turn are different decisions. If
strict placement inside brief silences is required and provider evidence is too
late, text-only timing cannot guarantee that requirement. Keep overlap-allowed
cues experimental or skip them; requiring local VAD is a separate scope decision.

## Transcript-driven prototype policy

Maintain a bounded rolling transcript/context per authorized human turn, keyed
by room incarnation, activation, connection/source generation, policy revision,
turn reference and transcript revision. Use replacement text, not concatenated
interims. An event-driven gate considers fresh lexical progress in an open turn
while in listener mode. A timer may throttle evaluations or reconsider a bounded,
unexpired candidate in the timing experiment; it cannot invent new speech,
confirmed acoustic silence or a turn endpoint. An optional pause signal may
admit an already selected candidate without requiring another changed transcript;
it cannot refresh that candidate's content lifetime.

Compare no cues, a conservative cadence rule and bounded semantic selection on
the same input. The user now explicitly allows the common listener/message result
to contain a backchannel such as “okayyy.” Production cue proposals use that common
schema, not a mandatory separate phrase_id response. A reviewed phrase bank and
phrase_id selector may remain experimental baselines/cache sources. Validate
proposed text for short neutral listening content, language/voice and freshness;
do not accept a main answer merely because the model labelled it listener.

Reuse configured model access with bounded read-only conversation context.
Cue evaluation has no business-tool execution and does not occupy or mutate the
ordinary main-request history loop. The model can propose a cue, but the room
owns purpose/identity and actual admission. The voice E quality gate still decides
whether timed audible cues can be enabled. Explicit idle is handled by the
admitted dialogue/control path, not by the cue selector. This change supersedes
the earlier requirement that semantic cues only return phrase_id/null.

Within those conditions, compare text-based timing estimates with optional
provider timing when actually available. Annotate short pauses, continuing
speech and true endpoints independently in the recorded audio. Measure false
pause estimates, evidence-to-playback delay, missed opportunities and audible
overlap; include uninterrupted speech with delayed/bursty ASR. Report missing
provider capabilities separately rather than silently falling back to a claim
of pause-aligned playback. Keep the provider's endpoint policy unchanged across
these comparisons.

Proposed experiment settings: earliest eligibility four seconds after the first
nonempty transcript, at most one evaluation per 800 ms with changed content,
five seconds between cue starts and at most three cues per human turn. Those
are transcript-observation/cadence limits, not measured speech duration. Sweep
them on validation data; they are hypotheses rather than approved defaults.

Start with an opportunity lifetime of 600 ms and clips no longer than 800 ms,
also subject to measurement. Limit one in-flight decision and one coalesced
latest opportunity per participant; bound node-wide work. Validate the current
revision before audio admission. For the initial prototype, changed revisions
invalidate pending decisions. Measure whether this causes starvation on fast
ASR streams; do not accept a stale decision merely to improve coverage. A later
prefix-compatibility rule requires explicit tests for corrections and negation.

Skip when text is stale/empty, the turn ended, the decider is uncertain or late,
output is busy, neither a prepared clip nor deadline-bounded synthesis is available,
an explicit idle hold is active, language/voice is unvalidated,
or a source/permission/hold/transfer barrier changed. Errors drop the optional
cue; they never initiate a normal answer. Endpoint/resume semantics remain owned
by the provider path. Never postpone a confirmed endpoint to find a cue slot.

Prefer neutral, very brief continuers. Agreement, reassurance and claims of
understanding can be inappropriate during complaints, serious disclosures,
corrections, consent, number dictation or stepwise verification. Include those
as skip cases. Use language-specific, listener-reviewed phrase/voice banks;
unknown or mixed-language uncertainty skips output rather than inserting English.
The incoming classifier's fourteen-language list grants no outgoing cue support.

## Audio preparation, priority and evidence

Prepare a few cue variants through the selected TTS voice outside the decision
path. Cache identity includes tenant, permitted service/voice/model/config
revision, language, phrase/prosody version and audio format. Bound storage and
preparation concurrency. Changing a voice cannot reuse old-voice clips. Do not
store credentials or human transcripts in keys or generated assets. Missing
assets skip cues and warm asynchronously without delaying call readiness.

Use a dedicated scoped preparation operation so warming cannot clear a live
TTS context. The default prototype uses prepared audio; compare on-demand TTS
as a measured alternative, with a hard deadline and no late playback. Cached
cues are still generated by the configured TTS, not generic sound effects.

The main response, protected opening, briefing, transfer and hold operations
have priority. Never queue a cue behind them to play later. Stop an active cue
at a confirmed human endpoint, permission loss or main-response admission,
using its exact output identity. Cap audio duration/bytes and keep existing
credit/backpressure. Cue failure should not restart the agent or its tools.

Keep cues audible while the human speaks, at a reviewed relative level; preserve
human input continuously. Verify actual browser/WebRTC and telephone behavior,
including ducking, mixing, clipping, speakerphone echo and sustained overlap.
Do not suppress real human text merely because it matches the cue text. Echo
cannot be solved reliably with a transcript word blacklist.

Record attempted, skipped, admitted, played and discarded cue outcomes with
purpose and qualified playback evidence. Exclude cues from normal assistant
turn counts and default response-triggering LLM history. Permitted transcript/
audio inspection and recordings should still truthfully show what was played.
Track synthesis/selector usage separately; cache playback is not a new TTS bill.

Use the shared [TTS timing/transcript contract](tts-playback-transcripts.md) where
the selected provider supplies timing. Keep generated cue text and qualified
played text distinct, including estimated or unavailable cutoffs. Such evidence
does not turn a listening cue into an ordinary assistant history exchange or
provide pause detection for incoming human speech. Timing absence does not block
the cue prototype.

## Alternatives and acceptance decision

- Pause-driven VAD/prosody detection is valuable comparison material but changes
  the no-local-VAD requirement if made mandatory.
- Periodic playback without fresh text can acknowledge silence or a dead ASR
  connection; punctuation-only rules mistake revisions for meaningful boundaries.
- Sending each interim to the ordinary agent loop risks duplicate answers,
  history mutation and unpredictable cost. Use an isolated, bounded selector.
- Generating arbitrary cue text/using on-demand TTS increases semantic and timing
  variability. Prepared reviewed phrases are the first prototype choice.
- A global backchannel boolean set on start/cleared on finish is vulnerable to
  late callbacks. Participant mode plus exact output purpose/identity keeps
  lifecycle decisions explicit.

Freeze a native-reviewed corpus with both useful opportunities and mandatory
skip cases before tuning. Compare audible naturalness, user speech continuity,
late/interruptive/misleading cues, opportunity coverage, cue-onset latency,
ASR delay, main-response delay, echo errors and resource cost. Measure timing
against recorded input/playback, not just transcript reception. The milestone
contains proposed pass criteria and failure scenarios. Nothing in the sources
establishes transcript-only production acceptance for Vxpipe.
