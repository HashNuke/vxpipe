# Mode messages and projections

Status: research/design amendment, 2026-11-16; no runtime, UI or database changes.
The user added STS greeting questions, event naming/scope corrections, listener
cue outputs and storage/JS impact, then clarified explicit stop-and-wait through
an idle tool with optional acknowledgment. This note keeps that evolving decision
separate from earlier superseded recommendations and from implementation progress.

## Request accounting

- [x] Explain how current speech-to-speech greeting wording is selected.
- [x] Confirm/document direct TTS for known LLM-agent greeting text.
- [x] Rename the proposed model notification caller_idle to idle_timeout.
- [x] Defer call_state_changed and cross-participant publication without removing existing variable access.
- [x] Use agent_mode/message for final dialogue, including listener-mode cues.
- [x] Explain that ordered chat does not prove preceding TTS finished; keep correlation internal.
- [x] Resolve stop/ignore ambiguity using the user's native idle tool and optional acknowledgment.
- [x] Audit @vxpipe/core/react, Console decoding, persistence columns and publications.
- [x] Assign implementation and acceptance tasks to meaningful checkpoints.

## Greeting source evidence

FirstMessage reads fixed/generated/wait_for_input from the resolved participant.
The outgoing handler defaults to generated; other participants default to
wait_for_input. The editor exposes those choices and fixed text. The generated
STS instructions ask for wording based on system instructions; fixed supplies
the authored text. GPT-Live also asks it to pause/listen after opening. These are
provider instructions, not proof of exact verbatim audio on every profile.

GPT-Live fixed opening buffers and checks exact transcript. ElevenLabs compares
normalized words before releasing fixed output. Google checks available transcript
but has a completed-turn no-transcript release path. Document those differences;
no provider calls or new conformance evidence were obtained in this task.

For LLM-plus-TTS fixed greetings, the existing coordinator records assistant text
and emits it without a model request. The new history boundary still needs truthful
zero/partial delivery handling before reuse. This path is explicitly covered in
message A; only generated mode requires wording generation. Native STS opening
continues through the provider rather than a separate ordinary TTS service.

Sources: [FirstMessage](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority/first_message.ex),
[direction defaults](../apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_spec/direction.ex),
[GPT-Live opening](../apps/vxpipe_call_engine/lib/vxpipe/providers/openai/gpt_live_opening.ex),
[GPT-Live verification](../apps/vxpipe_call_engine/lib/vxpipe/providers/openai/gpt_live_fixed_opening.ex),
[Google opening](../apps/vxpipe_call_engine/lib/vxpipe/providers/google/sts_opening.ex),
[ElevenLabs opening](../apps/vxpipe_call_engine/lib/vxpipe/providers/elevenlabs/realtime_session.ex),
[ElevenLabs verification](../apps/vxpipe_call_engine/lib/vxpipe/providers/elevenlabs/realtime_output.ex).

## Event scope and ordinary dialogue

The new model event is idle_timeout in either call direction; existing internal
CallerIdle names need not be mechanically renamed. Keep existing eligibility.
call_state_changed is deferred as requested. Existing permitted variables,
transfer context and variable tools remain. Their current system suffix can change,
so message immutability does not imply a globally immutable provider request or
guaranteed prompt-cache hits. Do not quietly remove business context to meet a
broader cache promise. Earlier state-event examples remain only historical notes.

Final model dialogue now has exactly agent_mode/message. Input dialogue uses
message consistently as well; runtime adds content type/participant attribution
when constructing history. Native tool formats and summary text remain distinct.
listener/null creates no output; listener/message proposes a bounded cue;
speaker/message proposes a main response. speaker/null is not a final dialogue
variant. Runtime mode changes only through admission/settlement. A listener/null
result cannot relabel an independently continuing main answer as listener.

The user does not require a separate finish-old-then-reply action. A new admitted
speaker response can replace its eligible old main output. Native tool rounds
are exceptions to simple user/assistant alternation, and even ordinary alternation
does not mean the earlier audio finished. Correlated output/generation state stays
in the application; no model-visible turn machinery is introduced.

## Resolved stop-and-wait design

The initial follow-up question asked whether listener/null during old audio meant
ignore or stop. User asked for a proposal because the old answer might nearly
have finished. I temporarily recommended retaining interrupt_agent to distinguish
those intentions and explained “yeah” versus “stop, give me a moment.” The user's
subsequent idle-tool proposal supplies the explicit action, so that recommendation
is superseded. No extra interrupt field is needed in final dialogue.

Proposed idle({duration_seconds:10}) is a native platform control operation. It
stops the exact eligible old output and cues, allows one associated optional
speaker acknowledgment (“Okay, I'll give you a moment”), then starts the quiet
interval after acknowledgment playback settles. With no acknowledgment it starts
after old-output settlement. During the acknowledgment actual mode is speaker;
during waiting it is listener, with no cues. The runtime must scope the allowed
acknowledgment so the idle hold does not suppress it or release unrelated speech.

Human input remains active. Fresh input cancels pending/active waiting and handles
that input normally; stale acknowledgment/timeout work cannot restart later.
Expiry settles the original-format tool completion and appends one idle_timeout
in a single serialized continuation. It must not create two LLM responses from
completion plus timer, or conflict with the ordinary idle timer. Early cancellation
records the outcome without independently prompting speech. No blocking sleep,
no indefinite acknowledgment wait, no transcript retention bypass.

Keep old speech playing while a model decision is pending. listener/null or a
filtered backchannel leaves it alone. An admitted idle or speaker replacement
stops only the correlated old output if still active; if finished, cancellation
is a no-op. A newer output cannot be stopped by the late decision. No remaining-
word estimate, almost-finished threshold or model-visible playback diagnostics.
Idle is not currently implemented: PlatformResult only has hangup/transfer effects.
The new operation needs explicit room-owned admission through the existing native
submission owner, including a side-effect-free decoded idle proposal for overlap.
Do not enable speculative business-tool execution as a shortcut.

## Storage and JavaScript findings

The relevant viewer is @vxpipe/react (Conversation/CallConsole), backed by
@vxpipe/core Message and timeline types. The Console presenter and browser decoder
currently project payload.content or payload.text as display text. Feeding a JSON
control string into those existing fields unchanged would display the JSON.
The plan preserves display text separately from the model's message field and
adds only required output-purpose/mode presentation metadata for cues/inspection.

There is no Ecto plain-content model-conversation table in the inspected path.
AgentRuntime.Message is in-memory; durable call_facts already has map/JSON payload
and source_policy plus identity, attribution, correlation, ordering and time
columns. The new design maps every existing column group, retains runtime authority,
and prefers decoded structured payloads for storage rather than forcing provider
wire string encoding into the database. Extra columns require an actual query/
constraint need; no invented role/mode column is mandatory. Legacy records need
explicit trusted format handling, not parsing any brace-leading human text.

Nested retention is a concrete issue: both current archive policy boundaries
remove only top-level content/text for transcript-disabled facts. New nested
message/cue/summary/raw payloads require coordinated filtering. Archive publications
also store versioned encoded contents/digests, so live view, archived facts and
published inspection need compatible deterministic readers. No blanket backfill or
silent immutable-publication rewrite is authorized.

Sources and full mapping: [storage/JS design](../docs/design/agent-message-projections.md).

## Checkpoint changes

- Added two message A tasks for storage/archive/publication mapping and JS/viewer
  projection with rendered browser acceptance; A now has 10 tasks.
- Added message D as a meaningful configured-call timed-pause slice: native idle,
  acknowledgment/timer lifecycle, input/expiry coalescing, prompt/config and real
  acceptance. Five tasks; C remains eight and B seven. Total 30 tasks, all open.
- Voice C now consumes message C/D, uses mode/message plus native idle and preserves
  exact output authority. E admits common listener/message cues; phrase_id is only
  an experimental comparison, not a required competing production schema. Voice
  remains 72 open tasks. Timing/CPU/language/retention obligations remain.
- Updated editable prompts, classifier/backchannel/TTS designs and iteration notes.
  No runtime/UI code or provider behavior has changed; no model weights added.

## Verification and review

Independent Astra xhigh review found no material findings. It checked current
source evidence, mode/message and idle contracts, scoped acknowledgment, timer
settlement, early input and duplicate-continuation prevention, cue gating and
stale-target protection. It confirmed message D → voice C → voice E is acyclic,
30 message tasks and 72 voice tasks remain open, and JSON examples decode once.
Its minor stale text:null label was corrected to listener/message:null.

Local checks passed across the 27 changed Markdown files: 345 local links,
51 heading anchors, balanced fences, 15 JSON blocks and six encoded-content
examples. Task grouping/counts are A10/B7/C8/D5 = 30 and
A11/B4/C17/D12/E17/F11 = 72. The index still has 65 ordered milestones,
50 complete and 15 pending. The historical Scribe completion suffix matches the
pre-edit snapshot verbatim. git diff --check passes; an explicit whitespace
check also covers untracked documents. Final status contains documentation only.

No runtime, browser, provider, database or latency verification was performed or
claimed. Those checks remain implementation acceptance gates. No commits made.
