# Voice agent input and output guardrails

Status: proposed design, researched 2026-11-11; not implemented. The
[milestone](../../labnotes/milestones/voice-agent-guardrails.md) owns implementation
order, detailed contracts and acceptance. This decision records why those contracts
were selected. It does not advertise guardrails as currently available.

## Decision

Add optional participant-owned checks to the text path of an LLM-backed agent.
Evaluate finalized input before starting its model request. Evaluate complete
candidate output before releasing text or audio. Each question describes a condition
that should block normal processing when true. Trigger when its estimated probability
is **greater than or equal to** its **Confidence threshold**, default `0.70`.

Use a separate guardrail capability, selectable from call defaults or overridden as
a complete participant selection. Initial adapters are Jev through the first-party
System One API and OpenAI Decisions. Keep provider protocols separate from turn
policy. Do not route either through the conversational model/tool loop.

Input rejection either supplies structured feedback to a response-only LLM request
or selects an authored response without invoking the conversational LLM. Output
rejection supplies feedback for bounded, response-only regeneration. Every attempted
check and candidate retains its identity in permitted transcript/inspection history;
rejected text is never presented as spoken output.

Native speech-to-speech support is deferred. A transcript that arrives after audio
has left the provider cannot establish a pre-speech guardrail. Enabled guardrails
on that response path must fail validation rather than imply protection.

## Research evidence

Three requested external implementations were inspected at pinned source revisions.
Their identifying names, URLs and identifying path prefixes are deliberately omitted
from repository artifacts. A source snapshot establishes the mechanisms inspected,
not all possible plugins or later releases. No external source code was copied.

| Reference | Inspected revision | Observed mechanism | Consequence for this design |
| --- | --- | --- | --- |
| A | `6f62bf0b48a4b8441e061012576f2393680d469b` | Global prompt rules cover scope, abuse and honesty. The pipeline builder places aggregation before generation and speech synthesis inside an agent-owned worker. No question/threshold enforcement stage was found in the inspected builder and prompting modules. | Prompt instructions remain useful, but enforcement must be a separate explicit stage. Keep checks in the agent activation lifetime. |
| B | `81b52236d65ac42a29aacf5a7f111bcb621fb6f5` | A completed-user-turn hook can edit context; a stop-response exception suppresses response generation. Model and synthesis nodes are overridable. Preemptive generation is separately managed and cancelled. | Check before generation, cover generated and direct-speech entry points, and disable speculative model work on guarded input. A hook alone does not supply audit history or bounded rewriting. |
| C | `9a3096c8e08fd0ec25da3de1aeec9531b99c4c7a` | Typed yes/no classifiers map to both requested APIs and batch named questions. Context gates hold model input. Frame filters preserve lifecycle frames; the inspected filter still awaits its callback before forwarding them. | Reuse the adapter/policy separation concept, but implement explicit cancellation, strict result validation and lifecycle responsiveness. Do not place a network check in a synchronous forwarding callback. |

This inspection found reusable mechanisms, not evidence that these sources already
implement the entire requested input feedback, fixed response, output rewrite,
two-decimal settings and per-attempt transcript workflow. The selected design is
Vxpipe's synthesis of those mechanisms and its own ownership requirements.

### Jev evidence

The first-party API is `POST https://api.typesafe.ai/v1/systemone`, authenticated
with Bearer credentials. Requests contain `model`, `state`, and a map of named
`questions`; a yes/no question uses `type: "noul"` and `instructions`. Match the
answer by its map key and read `noul`. This is the probability of yes, not the
separate confidence statistic used by other question types.
[System One reference](https://docs.typesafe.ai/api/system-one),
[Noul semantics](https://docs.typesafe.ai/primitives/noul).

The current documented version is `jev-1.14.0`; `jev-latest` is a moving alias.
Prefer a concrete version when calibrating thresholds and record the returned model.
The documented standard limits are 64k tokens per request and 32k per question;
there is no separate question-count cap. Do not silently enable long-context mode.
[Model catalog](https://docs.typesafe.ai/models).

The provider's guardrail cookbook screens input and output with batched questions
and application-selected thresholds. That supports the classification approach;
it does not establish voice latency or error rates for our questions.
[Guardrail cookbook](https://docs.typesafe.ai/cookbooks/llm_guardrails).
The HTTP reference documents a 32 MiB body limit and `429`/`529` backoff behavior.
Our tighter voice budgets take precedence over generic SDK retry defaults.
[Request rules](https://docs.typesafe.ai/api/errors).

### OpenAI Decisions evidence

Use `POST https://api.openai.com/v1/decisions` with Bearer authentication. The
current guide lists `gpt-6-luna` as the supported model. Supply shared `input` and
named predicate questions; map answers by `name` and read `probability`. The guide
allows 1–400 questions in a request. These are classification results, not generated
reasons or an execution mechanism.
[Decisions guide](https://developers.openai.com/api/docs/guides/decisions).

The endpoint can return a per-question `type: "refusal"` alongside answered
questions. A refusal has no usable probability. Treat it as an evaluation error,
never as a low risk score. Retain reported usage and returned model identity.
[Create-decision reference](https://developers.openai.com/api/reference/resources/decisions/methods/create).

No account access, paid inference, provider latency, classification quality or live
voice behavior was tested in this research. Model availability and API details must
be rechecked at implementation; documented speed claims are not acceptance evidence.

## Fit with the current implementation

The [call-spec guide](../en/usage/call-specs.md#models-and-speech) and
`CallSpecCompiler.effective_ref/3` already define whole-selection inheritance.
`CallSpec.Capabilities`, `CapabilitySelection`, the resolved plan, provider manifests,
credential planning and editor lookups all need the new capability; a UI-only field
would be discarded or rejected by the current parser.

`AgentRuntime.Coordinator.ActiveRequest.start_caller/2` currently starts
`Session.request` with caller text. `OutputBuffer` emits sentence segments while
`Coordinator.RequestOutcome` emits the final suffix. Both output paths must be held
when output checks are enabled. Waiting only in `RequestOutcome.finish/3` would
allow earlier sentences to escape.

The generic `AgentRuntime.RequestRunner` also commits assistant text into model
conversation. A publication hold alone would leave a blocked answer in subsequent
model context. Introduce a generic candidate acceptance/revision boundary before
final conversation commit, implemented by a Call Engine policy owner. Keep the
[runtime dependency direction](../en/development/agents-and-mcp.md): Agent Runtime
must not depend on Call Engine, tenant storage, speech or Console.

`TranscriptRouter` owns permission projection, not semantic classification. The
guardrail provider gets only content the target agent may receive. Room-owned
events, asynchronous archival, Calls inspection projections and Console renderers
must preserve that distinction. The new classifier does not grant transcript
access, rewrite media permissions or place SQL on the live path.

## Alternatives and implications

| Alternative | Decision and reason |
| --- | --- |
| Prompt-only instructions | Retain for response wording, but insufficient for an explicit threshold, pre-model gate or inspectable decision. |
| Reuse the conversational LLM selection implicitly | Reject: a conversation model may not support the decision endpoint. Inherit from a separate call guardrail selection. |
| Use a vendor's choice confidence for every question | Reject: certainty about a negative answer must not become a violation. Normalize probability that the blocking proposition is true. |
| Run input checks beside speculative generation | Reject for this milestone: the requirement is to check before passing input to the LLM; speculative tools could already have effects. |
| Speak and classify simultaneously | Reject: cancellation cannot retract emitted audio. Buffer the complete candidate; latency increases by generation buffering plus evaluation. |
| Classify sentences independently | Defer: unsafe meaning can span sentences. Whole-response checks provide a clear initial acceptance boundary. |
| Retry the whole model/tool turn | Reject: tool effects may already exist. Rewrite only the candidate response, without tools, preserving committed invocation outcomes. |
| Store only the winning response | Reject: it hides input rejection, failed candidates and checker outages. Preserve permitted attempt records separately from spoken history. |
| Let errors pass | Reject for enabled checks: unavailability is not evidence of a pass. Fail the affected turn explicitly and remain ready for subsequent input. |
| One shared checker process for all calls | Reject: slow work and cancellation would couple participants. Use owned bounded workers; connection pooling must not own call work. |

Whole-response gating trades away early sentence playback only for participants
with output checks enabled. Input-only configurations retain ordinary output
streaming. Classification is probabilistic: the release invariant is that no
candidate bypasses an enabled check, not that every harmful response will be
detected. Thresholds require a labeled corpus including negation, quotation,
ambiguous language and multi-turn context.

Text guardrails also do not roll back tools or enforce business authorization.
Input rejection disables tools in the resulting response. An input that passes
may legitimately cause tool work before its final text is checked. Existing tool
permissions remain authoritative; separate tool-argument/result guards are future
work. Bounded rewriting must never repeat those effects.

## Verification and design review

The source review identified five integration hazards: sentence leakage before a
verdict, blocked answers committed to model context, tools repeated by regeneration,
late checks crossing an activation boundary, and sensitive text leaking through
debug/error events. The milestone gives each an automated acceptance case.

The review also separates input rejection from checker failure, covers generated
greetings and background-tool continuations, and preserves the original caller
text without inventing speech for decision records. It uses the existing read-only
debug host; completion of its unrelated live interaction features is not a dependency.

This is a local design/source review, not independent review or implementation
verification. Documentation checks and research provenance are recorded in the
[labnote](../../labnotes/20261111-1019-voice-agent-guardrails.md). Implementation,
rendered browser checks, deterministic protocol tests and hosted acceptance remain
unchecked in the milestone.
