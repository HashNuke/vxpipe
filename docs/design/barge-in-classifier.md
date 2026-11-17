# CPU barge-in classifier integration proposal

Status: research proposal, 2026-11-16. No runtime behavior or dependency changes.
This supplies the LLM-plus-TTS classifier design for checkpoints C, D and F of
the [combined voice milestone](../../labnotes/milestones/voice-agent-turns-and-listening.md).
All implementation tasks live there. This research does not complete its
endpoint, multilingual or audible-latency acceptance gates.

## Recommendation

Run the released INT8 ONNX classifier as a shared, node-local internal service,
with bounded asynchronous admission and CPU inference workers. Give each eligible
voice-agent participant a small policy process that owns overlap candidates,
transcript revisions and decisions. The room remains the authority that validates
and applies output cancellation and caller-turn dispatch. Never run inference
inside a room callback, the agent coordinator, or a participant policy callback.

The classifier is an input filter ahead of the LLM, enabled by default for newly
added agents and individually disableable. Its effective use remains subject to
LLM-plus-TTS and language eligibility. An accepted
backchannel skips LLM input and leaves playback running. Other speech, including
speech with no applicable classifier, goes to the agent LLM with minimal
structured participant input and frozen agent_mode. The LLM returns a structured
decision about interruption and whether/what to answer. A positive classifier
result admits LLM consideration;
it does not itself cancel output in this design. This incorporates the user's
follow-up and supersedes the initial proposal's immediate-interruption fallback.

Use ONNX Runtime through Ortex, already present for Silero, and the Hugging Face
tokenizer through Elixir Tokenizers. First expose per-session CPU thread controls
in the binding and prove tokenizer/runtime parity. Ship the model inside the
distributed container, downloaded and verified during its build. **Never commit
model weights, model binaries, tokenizer artifacts, or model Git/LFS history to
this application repository.** Commit only a small artifact manifest, integration
code, focused fixtures, and build instructions.

## Findings and evidence

Inspected Vxpipe at `64a4626a`, classifier source at
`294dc3fd39749ccfe353fb08d5089066199b1049`, and the local HF model submodule at
`28177ae331b8ee751ab2a1bb62da5c5632b8473f`. The latter is the proposed immutable
artifact pin, subject to full build verification. The selected release is
`HashNuke/barge-in-detector` v0.2.0. A moving release tag is insufficient as a pin.

The source checkout's `docs/e5-phrase-results.md`, `training/onnx_infer.py` under
`barge_in_detector/`, cleaner, and HF release manifest establish:

- Input is one cleaned human utterance, with no agent text, speaker label,
  language hint or `query:` prefix. It is an overlap classifier, not a contextual
  dialogue model or an endpoint detector.
- Cleaner v1, first 64 tokenizer tokens including special tokens, right
  truncation, int64 `input_ids` and `attention_mask`, float logits of shape
  `[batch, 2]`. Labels are `backchannel=0`, `barge_in=1`; return softmax index 1.
- Probabilities are uncalibrated. The release's 0.5 cutoff is diagnostic, not an
  established production operating point.
- Declared languages: `en hi kn ta te ml zh ja id fil fr de es it`. Training
  includes native scripts and English code-switching; that does not establish
  arbitrary transliteration or code-switch coverage.
- INT8 is approximately 406.8 MB, versus 470.7 MB FP32; embeddings remain FP32.
  Per-worker/session RSS is unmeasured. A pool can multiply substantial memory.
- Warm INT8 batch-one p99 is 5.69 ms on typical inputs and 18.85 ms at the full
  token budget, on the designated EPYC-Genoa CPU using **four intra-op threads**.
  These exclude service admission, queueing and call control. They do not
  establish one-core speed, a hard maximum, current-release cold start, or
  caller-perceived interruption latency.
- Reviewed English development evidence is 94/98, including four missed
  interruptions. The reused set and synthetic multilingual results do not
  establish production accuracy. Known misses include `repeat`, `enough`,
  `go back`, and `got it okay now let me explain`.

The current [input handler](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority/input_turns.ex)
calls `AgentOutput.interrupt/2` in `begin_audio_turn/4`, before transcript
publication, including empty-text onset. At turn end it publishes text and
unconditionally attempts ordinary LLM dispatch for nonempty eligible input.
Both paths must change for the new semantic interruption policy, whether or not
it uses the classifier. Filtering a transcript
subscriber alone is too late to save playback and cannot prevent a new response.

The [output handler](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/room_authority/agent_output.ex)
already owns TTS cancellation, model cancellation, tool cancellation, interrupted
events and played-history settlement. Reuse that machinery behind a target-qualified
admission boundary; do not reproduce it in the classifier or participant process.
Its current interruption function clears the logical output lane, so calling it
with an old asynchronous decision without checking the output generation is unsafe.

The current `ParticipantTranscription` event is replacement text for one turn.
It lacks detected language and the complete internal source-generation identity.
Use an authorized internal delivery contract carrying that identity; do not
construct control authority from a broad public event subscription.

## Ownership and lifecycle

```text
Call Engine application supervisor
  BargeIn inference supervisor
    admission/dispatcher process
    bounded inference workers (resident ONNX sessions + tokenizer)
  room/participant supervision
    LLM voice-agent participant
      BargeIn policy process (no model weights)
      existing agent activation/runtime

authorized STT -> room -> participant policy -> optional inference service
                            <- correlated score
                            -> backchannel: retain transcript, skip LLM
                            -> otherwise: structured LLM decision request
                            <- interruption + response disposition/text
room <- validated decision -> existing cancellation / response admission
```

Suggested cohesive modules: `BargeIn.Classifier` (contract and inference),
`BargeIn.Dispatcher` (capacity/deadlines), `BargeIn.Worker` (resident session),
and `BargeIn.Policy` (participant filtering/decision coordination). Keep them in
Call Engine initially; it already owns speech, Ortex and interruption. No new umbrella application or
external HTTP API is needed for this slice.

Attach policy as a conditional child beneath `ParticipantSupervisor`, alongside
the existing activation, with its own restart budget. Avoid putting optional
policy failures into the activation graph's current `one_for_all` group, where
they would restart the LLM/tools/MCP runtime. Bind policy state to the exact
activation generation; activation restart invalidates pending decisions. Normal
classifier errors become fallback outcomes, not process crashes. Policy recovery
invalidates pending decisions and rebinds to a fresh room snapshot. Keep playback
running while unavailable; use the bounded decision-failure handling below.

The shared service survives individual calls and transfers. Policy and pending
requests end with participant teardown; replacement/transfer invalidates the old
activation. Worker loss produces bounded unavailability and independent restart.
Name supervisors/registries explicitly. A classifier outage must not restart
rooms, stop call ingress, or make an unselected call depend on model readiness.

## Policy and turn semantics

Semantic policy eligibility requires an LLM-plus-TTS agent, room-owned
interruption, permitted human input/transcripts, and an interruptible output
interval of a main response overlapping that human turn. Listening-cue playback
does not create that eligibility: the separate
[agent backchannel proposal](agent-backchannel-responses.md) keeps those outputs
in listener mode while human input continues. Classifier filtering additionally requires
an enabled preference (default on for newly added agents), readiness and a
supported/validated language profile. Without
that filter, the same semantic policy uses the structured LLM path directly.
STS participants are excluded, including STS profiles with transcripts.
Typed text, protected opening audio, private briefing, hold/transfer barriers
and generation without overlapping playback retain their existing contracts.

Capture eligible output identity at human onset using existing sink/output
evidence. Server egress is a qualified proxy for audibility; do not claim remote
hearing without playback evidence. Policy receives permitted activity even when
text is empty, but only submits nonempty cleaned text. No speculative mute,
pause, buffer-clear or model cancellation is allowed while awaiting classification.
The same rule applies while awaiting an LLM decision.

| Candidate state/evidence | Proposed behavior |
| --- | --- |
| No relevant overlap when the human turn starts | Ordinary input; a standalone `yes` remains a valid answer. |
| Eligible overlap, no usable transcript yet | Continue output; retain bounded activity state. There is no text to classify or submit to the LLM yet. |
| Current revision accepted as backchannel | Continue output; skip LLM input; retain evidence; reevaluate changed replacement transcripts. |
| Classifier returns barge-in or uncertain | Submit the current text and frozen agent_mode to the structured LLM decision path. |
| Classifier disabled, unsupported, unavailable, overloaded or timed out | Bypass the filter and submit usable text to the same LLM path. |
| LLM says keep speaking, no response | Leave generation/playback untouched; consume this revision without a new answer. |
| LLM says interrupt, no response | Latch interruption for this caller turn; stop the captured output once and keep listening. |
| LLM says interrupt and respond | Stop the captured output; admit its validated response after the human turn ends. |
| LLM says respond without interruption | Admit its validated response after both the human endpoint and current playback settlement. |
| Backchannel or LLM-ignored turn reaches the provider endpoint | Settle it without ordinary LLM response dispatch, subject to reevaluating changed final text. |

Keep original text and replacement-transcript semantics. `yes` evolving into
`yes, but change the appointment` is one caller turn, not appended duplicate
drafts and not a permanently ignored acknowledgment. Once cancellation commits,
a later lower score cannot restore discarded audio. Prefix false positives
therefore matter as much as final-utterance accuracy.

One irreducible ambiguity is an early answer: `yes` while the final words of an
agent question are still playing can be an answer rather than a backchannel.
The text-only model cannot distinguish those identical inputs. Include these
cases in acceptance. Where the application explicitly knows it is accepting an
early answer, bypass backchannel suppression for that phase. Inferring this
phase from punctuation or an LLM prompt is not a proven contract; absent such
evidence, a profile that fails these cases cannot be advertised as fully
contextual interruption handling. Such ambiguous phases can bypass the filter
and use the LLM's conversation context; discarded text never reaches that LLM,
so it cannot repair a classifier false negative afterward.

At an endpoint, reevaluate changed final text and wait only for the bounded
outstanding semantic decision; do not install another endpoint settling timer.
Classifier budget expiry bypasses the filter; LLM failure follows the explicit
failure policy below. An STT final segment remains distinct from a true endpoint.
This proposal does not change provider endpoint authority.

If the captured agent output ends while classification is pending, retain the
candidate's overlap provenance. A valid late interruption can still admit its
caller turn, but it cannot cancel a newer agent output. A backchannel that
finishes just after agent playback remains a backchannel candidate. If new
substantive words arrive after playback ends, treat that continuation as ordinary
input unless a fresh eligible overlap exists; do not suppress a new answer on
the strength of an earlier acknowledgment. Test this boundary explicitly.

Transcript events/archive evidence remain subject to existing permissions and
retention. Record disposition separately from the original transcript. Do not
call the existing model-dispatch or spoken-history confirmation path just to
store a backchannel: that would create an answer or distort ordering. Initially
keep backchannels in permitted transcript/history evidence without injecting
each one into the active LLM conversation. Future model-context inclusion needs
an explicit non-triggering, ordered contract.

## Structured LLM decision contract

This is a proposed contract, not an existing API. Use the configured agent LLM,
authored instructions plus stable platform protocol instructions, and a bounded
read-only snapshot of permitted conversation history. Use the common
[structured message protocol](structured-agent-messages.md). A completed
overlapping utterance uses the same minimal participant input as ordinary speech:

```json
{
  "type": "participant_message",
  "participant_id": "human-1",
  "message": "Yes, but change the appointment to tomorrow.",
  "agent_mode": "speaker"
}
```

Capture agent_mode at initial input admission before processing changes mode;
retain it in history. It is not proof of acoustic overlap or permission to stop.
The runtime keeps output intervals, candidate/revision identities, current
eligibility, generated text, played-prefix evidence and classifier scores/bypass
reasons internally. Do not send agent_output, classifier or playback diagnostics
to the model. The classifier filters before LLM submission; admitted and fallback
input share the same format. Test semantic quality under this deliberately
smaller input contract, including uncertain short replies and corrections.

The [TTS contract](tts-playback-transcripts.md) normalizes optional alignment for
the application. Ordinary model history receives supported spoken text only;
generated output and unknown delivery remain internal. Preserve original native
tool calls/results and existing engine completion observations, without adding
mode or pending-status snapshots. A speculative decision cannot execute tools;
it may only decode an idle proposal for subsequent authorized room admission.
Participant text remains untrusted data and cannot set trusted envelope fields.
The common final dialogue result now uses agent_mode and message. Native idle
is a separate explicit stop-and-wait action, not an interrupt_agent response flag.
The [message design](structured-agent-messages.md) owns the complete contract:

```json
{
  "agent_mode": "speaker",
  "message": "What time tomorrow would you prefer?"
}
```

listener/null leaves existing output alone. listener/message is a cue candidate
only when the shared cue gate allows it; it cannot turn an ongoing main answer
into listener-mode audio. speaker/message requests a new main response, whose
admission replaces only the eligible old response. speaker/null is invalid.
There is no independent finish-old-then-reply action. Reject malformed/refused/
incomplete output and do not speak control JSON. Runtime output purpose, current
mode and cancellation authority are not directly writable by returned fields.

For “stop talking, give me a moment,” the model may propose the native idle tool
(duration_seconds=10 in the accepted example), optionally followed by a validated
speaker acknowledgment. Room admission stops the eligible old answer, permits
that scoped acknowledgment, then starts the quiet timer after playback settlement.
Fresh user resumption cancels the wait; expiry produces one idle_timeout with
original-format tool completion in one continuation. See message checkpoint D.
No remaining-audio estimate is needed: a finished old target needs no cancellation,
and a late idle/response decision cannot stop a newer target.

Partial-input evaluation may propose no output, a gated cue or an early idle
stop. It cannot execute speculative business tools or emit a main answer before
input admission. The idle proposal itself has no side effect until exact-target
room validation and submission through the existing authorized native-tool owner.
An idle callback/acknowledgment is scoped to its operation, and cannot mute new
human input or reset a newer response. Completed input still receives one final
evaluation when required; do not duplicate tools, acknowledgments or follow-ups.

The existing [Session](../../apps/vxpipe_agent_runtime/lib/vxpipe/agent_runtime/session.ex)
accepts one active request, and the Call Engine coordinator queues ordinary
inputs behind it. Sending these decisions through that queue could defer
interruption until the old response finishes. Add a bounded decision request
beside active generation, using a read-only conversation snapshot and the same
agent configuration, with native idle enabled only as a validated control proposal. It must not cancel or mutate the active request to acquire
that snapshot. Coalesce revisions, bound per-participant/node model concurrency,
and account for this path's additional provider requests and usage.

The existing [ModelResponse](../../apps/vxpipe_agent_runtime/lib/vxpipe/agent_runtime/model_response.ex)
requires text or tool calls, and normal streaming forwards text deltas toward
TTS. Use the explicit typed result and provider normalization path owned by the
[message-format milestone](../../labnotes/milestones/structured-agent-messages.md):
a valid no-response result is successful, control JSON is never spoken, and
response text cannot reach TTS before the decision is validated and admitted.
Keep speech semantics in Call Engine and generic generation/structured-result
handling in AgentRuntime. Do not expose playback control through the generic
external-tool executor.

Only the existing conversation owner commits an admitted user/assistant exchange.
For a replacement, first settle cancellation and the played assistant prefix;
then commit the accepted input and response once. An admitted idle call retains
its native call/result pairing and associated acknowledgment exactly once. Discard speculative histories
and never overwrite newer tool/context commits. Snapshot conflicts require
bounded reevaluation of the latest eligible candidate. Expected playback progress
alone must not trigger endless reevaluation. Room validation can apply a pending
answer if the targeted output has simply finished, but cannot cancel a newer
generation. A listener/null decision leaves ongoing generation/history untouched
and records its disposition in permitted call evidence.

Classifier failure and LLM decision failure have distinct outcomes. The former
immediately bypasses filtering. For LLM failure, propose one bounded retry of the
latest revision within an absolute decision deadline; keep current playback
running. On exhaustion, expose a recoverable decision failure and retain the
completed input for ordinary handling after current output settles, subject to
existing source/permission/turn checks and provider failure handling. Never
silently label failed decisions as backchannels or invent a stop decision.
This degraded path can cause an unnecessary later answer and needs explicit
acceptance coverage. It is separate from a deliberately selected legacy policy.

## Request correlation, bounded work and fallback

Each request carries tenant/room/incarnation, listener agent and activation,
human participant/connection, source allocation/turn reference, policy revision,
caller turn, replacement-text revision, captured output identity, artifact
revision, request reference and a monotonic absolute deadline. The response
echoes correlation and returns a finite score or a typed unavailable result.
That is the classifier contract. LLM requests carry the same candidate/output
identity plus the conversation snapshot version, and return the control result
above. Policy uses classifier evidence to filter; the room validates and applies
LLM decisions.

On receipt, the room rechecks the current participant, activation, source,
permission/hold state, candidate revision and target output before mutation.
An obsolete revision cannot suppress input or cancel anything. Decision
deduplication must ensure one admitted response per completed caller turn.
Early decision requests are distinct from response admission and cannot publish
competing answers.

Keep at most one running request and one coalesced latest revision per candidate.
Bound candidates per participant and admission across the node; apply fair
per-participant scheduling so one rapidly revising STT stream cannot starve
other calls. Reject overload immediately rather than accumulating GenServer
mailbox work. Cancellation removes queued work; executing native inference may
continue, remains charged against capacity, and its obsolete result is discarded.
A `GenServer.call` timeout or killing a BEAM task does not prove native work stopped.

Provisional classifier measurement setting: a 50 ms transcript-to-filter service
budget, after which usable input bypasses the filter. Bound activity state and
its lifetime even when no transcript arrives; missing text cannot produce an
LLM decision. The LLM path needs its own measured deadline, input/output limits
and retry budget. The earlier 250 ms observation fallback to immediate
interruption is withdrawn. Changed text needing a fresh decision gets a bounded
budget; repeated revisions cannot extend unresolved work forever.

Use a validation-selected threshold to accept backchannels; all other usable
speech reaches the LLM. A second threshold may label likely interruptions for
diagnostics, but is not required for this filter. Shadow mode can record 0.5 labels;
live thresholds require calibration. Unsupported/unknown classifier language,
missing model, saturated pool, timeout and invalid logits route usable input to
the LLM. If cleaner output is empty but the original transcript has meaningful
content, bypass classification with that original text. Actually empty/noise-only
input is activity evidence, not a fabricated caller response. Policy recovery
cannot reuse old decisions.

The model only sees the first 64 tokens. A long acknowledgment followed by a
correction beyond token 64 would otherwise remain invisible forever. For live
policy, detect overflow and forward to the LLM; do not silently
truncate and accept backchannel. Do not switch to last-64/sliding-window input
without separate evaluation against the trained first-64 contract. Also bound
raw transcript bytes before normalization/tokenization; 64 model tokens do not
bound preprocessing cost.

## Language selection and compatibility

Keep three separate sets: model-declared languages, deployment-validated
languages, and languages enabled for the participant/source. Their intersection
is eligible. Pin them and the policy version with the prepared call snapshot.
The corpus covers fourteen languages; initial fresh human evaluation should
prioritize English/Hindi, with Kannada acceptance including `oudhu`, its scripts
and actual ASR variants. No language is production-validated by this research.

Use configured STT/input language initially: current events do not expose detected
language. A fixed supported/validated language uses the enabled filter by
default. Auto/mixed-language profiles
must declare a wholly supported and validated set to use the classifier;
otherwise they use the structured LLM path in languages supported by that agent.
This cannot guarantee per-utterance language detection: short words such as `yes`
are insufficient, and the classifier does not return a language. If strict
per-utterance gating is required, add trustworthy recognizer language evidence
as a separate contract before enabling auto mode. Never infer language from the
agent's prompt or TTS voice. Normalize regional codes through a reviewed mapping;
do not silently equate `fil`, `tl`, transliterations or all Chinese variants.

Propose a semantic interruption policy in the call spec with a classifier filter
that defaults to enabled for newly added agents, resolved to a pinned policy and optional bundled artifact/
language profile. The intended new LLM voice-agent contract uses structured
decisions both with and without that filter.
Its exact schema is implementation work; no new working configuration is claimed.
Preserve existing DB-configured STT/LLM/TTS services. The local model needs no
tenant API credential or model-serving URL. Global runtime settings describe
artifact location and capacity, not call-level enablement. Missing policy means
legacy behavior only when decoding old published revisions and existing running
calls; do not silently switch those calls when the container changes. Apply the
default-on preference when adding a new agent and preserve an explicit disabled
value through saving, publication and runtime resolution. A new-policy call
without the classifier still uses LLM decisions; it does not become legacy.
STS participants keep their own interruption policy. The default classifier
preference is inapplicable there and must not enable classification or make
adding an STS agent invalid.

### Implementation reminder — agent properties sidebar

User requirement, 2026-11-16: add a setting to disable the barge-in classifier in
the **agent properties sidebar → Models tab**. Newly added agents start enabled;
switching it off bypasses the classifier and retains structured LLM interruption
decisions. The preference does not override language or LLM-plus-TTS eligibility.

The UI is deferred. When promoting this proposal to implementation, create the
UI and configuration tasks for the toggle, persisted default/explicit-off values,
published-call propagation and browser verification. This note records the
requirement; it creates no UI implementation task or completion claim now.

## CPU concurrency and ONNX binding

OTP already uses multiple available CPUs by default and accounts for detected
CPU quotas. `+S` controls BEAM scheduler threads; it does not assign a GenServer
a dedicated CPU or control ONNX Runtime's native threads. Keep VM defaults
unless measured deployment constraints justify an override. Inspect online
schedulers and quota/cpuset limits at startup. See the
[OTP 28 runtime flags](https://www.erlang.org/docs/28/apps/erts/erl_cmd.html).

Separately configure inference concurrency and threads per inference. Start
with **one worker and one intra-op thread on a one-vCPU allocation**; benchmark
additional workers on larger allocations, initially one thread each. Compare
that throughput profile with one worker using two/four threads for latency.
Keep `workers × intra_op_threads` inside an explicit inference CPU budget and
leave headroom for BEAM/media, Silero and tokenization. More threads need not be
faster. At 20 ms actual service time one serial worker has a theoretical 50
requests/s ceiling before overhead; p99 is not mean service time, and latency
requires operating below saturation. Requests/s are not calls/s.

The [pinned Ortex binding](https://github.com/elixir-nx/ortex/blob/450dbe6ec6cc96e4e5509a746937ccde25de0144/native/ortex/src/model.rs)
only exposes provider and optimization selection at load, not intra-op/inter-op
limits or spinning. Its `run` NIF is marked `DirtyIo`, despite CPU inference.
Before shipping, use a reviewed binding extension/upstream revision exposing
session thread limits, sequential execution and spinning controls; assess moving
CPU inference to dirty-CPU scheduling, including Silero regressions. Do not
assume `OMP_NUM_THREADS` controls every ORT build or that `+SDcpu` fixes a
`DirtyIo` binding. ONNX thread settings are documented
[here](https://onnxruntime.ai/docs/performance/tune-performance/threading.html).

Use batch one initially: quantized scores can change with batch composition,
and microbatch waiting adds latency. Each worker can initially own one session
and immutable tokenizer. Measure RSS before increasing workers; a shared-session
design may reduce duplication, but requires a binding concurrency and throughput
probe. Elixir [Tokenizers](https://tokenizers.hexdocs.pm/Tokenizers.Tokenizer.html)
can load the artifact tokenizer. Match cleaner v1 golden cases, special tokens,
padding, truncation, masks and logits against the Python reference. No PyTorch,
Python server or embedding-model reconstruction is needed at runtime.

## Container artifacts and readiness

The app repository owns a small manifest with HF repository, full commit,
relative artifact names/hashes, cleaner/tokenizer contract, labels, language
manifest, licensing and policy compatibility. Build tooling downloads into an
ignored build cache outside tracked source; no Git clone/submodule or model
release history is copied into this repo. A build cache is optional, not a
runtime model registry.

Copy only INT8 ONNX, its tokenizer/metadata, provenance and required licence/NOTICE
files into a read-only container resource directory. Do not copy FP32/PyTorch
weights, training data or the source checkout. Verify bytes rather than accepting
an LFS pointer or successful HTTP status. Pin the tokenizer/runtime dependencies
too. Proposed INT8 SHA-256:
`d8b8f606e5fda9ef9b64c908c222402e3385d9d46f4ff00f2841aa7493845c6b`.
Tokenizer SHA-256:
`255f5e32cb320b4dc2b31e0f203832fecafe87ca4cc87c3c41eb8ccae73f441a`.

No downloads on call admission or application startup. An embedded/source
consumer can provision the same pinned artifact into a configured local path;
absence bypasses the filter under the new semantic policy. At startup verify manifest/hashes, load and
warm the configured workers, then advertise classifier readiness separately
from call-engine readiness. Use structured LLM decisions while the classifier is
unavailable and expose the reason. A bad model should not make unrelated calls
unavailable. Do not hot-swap the model of a pinned live policy; upgrades requiring
both versions either retain both resident versions or drain old-policy calls.

The graph contains ORT-fused contrib operators. Successful ONNX export alone
does not establish every runtime version/CPU architecture supports them; use
the [runtime compatibility guidance](https://onnxruntime.ai/docs/reference/compatibility.html)
and release-container smoke tests. Native NIF faults share the BEAM failure
domain; GenServer supervision cannot isolate a native crash. If that risk or
binding maintenance is unacceptable, retain the same Elixir service contract
and use a supervised executable through a
[port](https://www.erlang.org/doc/system/ports.html), packaged in the same image.
That alternative needs explicit OS-child cleanup, framing, backpressure and RSS
measurement; it is not the first choice for this ONNX-in-app request.

## Alternatives and implications

- A model per participant duplicates hundreds of MB and repeats cold loading;
  participants should own policy state, not model instances.
- One unbounded GenServer inference queue is simple but lets interim transcripts
  become stale and causes head-of-line delay across calls. Bound admission and
  give native workers a separate responsibility.
- A separate HTTP/Python deployment adds a network dependency and another
  operational unit despite an existing native path. Keep it as a fallback only
  if native compatibility or isolation requires it.
- Immediate onset cancellation followed by classification cannot restore
  continuous playback. Muting while deciding also violates backchannel behavior.
- A word allowlist cannot distinguish an answer from overlap, and the same word
  can begin a correction. The runtime supplies temporal context; this model
  cannot supply missing conversational semantics or acoustic emphasis.
- Structured LLM decisions supply dialogue context for forwarded input. They
  cannot recover speech wrongly filtered out by the classifier, and their added
  latency needs measurement. Acoustic modeling would be a separate contract.

## Verification performed and proposed delivery

Research smoke verification: `bin/setup` completed. The existing pinned Ortex
loaded the released INT8 graph on OTP 28 and executed real int64 tensors. Eight
batch-one examples were tokenized/cleaned by the classifier's Python reference
and run through Python ORT and Elixir Ortex: English acknowledgment/interruption
and developing correction, Kannada/Hindi acknowledgments, and two 64-token
inputs. All eight diagnostic labels agreed; maximum absolute probability
difference was `9.775842447012906e-5`. This tests inference compatibility only:
Elixir cleaner/tokenizer parity, accuracy and serving latency are unproven.
The local INT8 and tokenizer bytes also matched the two SHA-256 values above.

The first diagnostic attempted nonexistent `Ortex.Model.show/1`; a subsequent
model inspection also exposed an existing Elixir 1.19 Inspect implementation
error. Neither prevented successful inference. Avoid relying on struct inspection
for the model contract; use explicit boundary validation. No dependency repair
is included in this proposal.

The [combined milestone](../../labnotes/milestones/voice-agent-turns-and-listening.md)
is the sole delivery checklist; this specification groups its requirements as:

| Checkpoint | Requirements from this specification |
| --- | --- |
| C — Structured interruption and participant modes | No-classifier semantic decisions, common assistant response, active-generation concurrency, endpoint/failure handling, room authority, modes/purpose and ordered history. |
| D — CPU backchannel filter in configured calls | Artifact/tokenizer/runtime parity, thread controls, bounded serving and participant filtering, language/default-on preference, deferred Models-tab task creation, build packaging and first validated configured call. |
| F — Telephone calls and validated language coverage | Additional profiles/languages, native Kannada/ASR review, CPU/quota/load and runtime-architecture coverage, combined audible and latency acceptance. |

TTS precision is optional and supplied by A/B. Component research/serving steps
are tasks inside D, not independent product checkpoints. The
[delivery review](voice-conversation-iterations.md) records consolidation rationale.

Before enabling live decisions, freeze per-language false-stop and missed-stop
limits, score thresholds, and latency budgets against fresh validation data;
keep acceptance data separate. Measure queue wait, preprocessing, native time,
LLM admission/decision time, policy/room delay and sink cancellation separately.
Report p50/p95/p99/max, timeouts, filter bypass rate, decision-failure rate,
LLM requests/cost, stale drops and memory. The 50 ms transcript-to-filter
target is separate from LLM latency, onset-to-transcript latency and audible stopping time;
neither proves the milestone's 1,000 ms ordinary-response target. Telemetry must
avoid raw transcript text and high-cardinality call IDs in metric labels.

Specification review: locally checked ownership, dependency order, asynchronous
staleness, endpoint races, input overflow, model pinning and failure handling.
The follow-up review additionally checked the no-classifier LLM path, successful
no-response semantics, active-request concurrency, structured-output validation,
history commit ownership and the dependency on the semantic baseline before
classifier activation. This is
not independent review, implementation acceptance or authorization to deploy.
