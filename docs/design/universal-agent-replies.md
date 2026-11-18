# Universal structured replies for LLM integrations

Status: implementation and acceptance in progress, 2026-11-18. Shared eligibility,
transport strategies, bounded correction, private replay and authoring/browser
compatibility are implemented. Remaining provider live acceptance and final
conformance/release gates remain open; Zenmux live checks are explicitly deferred
by the user, while its deterministic coverage remains required.
The user's requirement is definitive: remove the structured-reply allowlist and
support the shared agent response contract across every LLM integration.
The contracts below govern implementation; the milestone records completed
behavior and remaining acceptance evidence.

Implementation owner: [milestone](../../labnotes/milestones/universal-agent-replies.md).
Research evidence: [labnotes](../../labnotes/20261118-1435-universal-agent-replies.md).
This supersedes the OpenAI-only eligibility policy in the
[structured-message design](structured-agent-messages.md), not its message,
history, tool, privacy, settlement or idle contracts.

## Findings at investigation

The common response is validated by `Vxpipe.AgentRuntime.Dialogue`: exactly
`type: "participant_message"`, `participant_id`, `agent_mode` and `message`,
with listener/null, listener/text and speaker/text allowed. All four fields are
required. Duplicate keys, unknown fields, invalid attribution, blank text and
speaker/null are rejected. The participant ID uses the same bounded syntax as
settled history. Returned attribution is descriptive: the normalized Dialogue
contains only mode/text, and the host still owns actual speaker identity.
RequestRunner buffers modern replies and decodes the complete final result before
speech admission. Native tool rounds remain distinct from dialogue.

At the investigation baseline, the restriction appeared at several boundaries:

| Boundary | Baseline implementation | Required change |
| --- | --- | --- |
| Call-plan validation | `CallEngine.AgentProtocol.supported_participants/2` calls ReqLLM's model-support predicate | Remove protocol eligibility by provider/model identity; keep real source, credential, tool and protocol-version validation. |
| Session configuration | `SessionConfiguration` checks `supports_protocol?/3` | Validate the shared protocol implementation and options, not membership in a model list. |
| ReqLLM profile | `Provider.ReqLLM.DialogueProfile` accepts only `openai/gpt-6-luna` and Responses wire | Remove the allowlist, including implicit equivalents in replay validation and options handling. |
| Outbound requests | `RequestProjection` always supplies OpenAI-style strict `response_format` through provider options | Express one semantic reply contract; select provider wire encoding internally without changing the contract. |
| Inbound history | `ResponseNormalizer` and `RequestProjection` call `OpenAIReplay` directly | Keep bounded replay ownership, but preserve each integration's required continuation metadata. |
| Acceptance | Modern live dialogue coverage is OpenAI-specific; other LLM tests are not equivalent proof | Registry-driven shared conformance plus real complete conversations for every integration. |

The six installed production `:llm` manifests are Google AI Studio (`google`),
OpenAI (`openai`), DeepSeek (`deepseek`), Fireworks (`fireworks`), OpenRouter
(`openrouter`) and Zenmux (`zenmux`). All point to the same production ReqLLM
adapter. They are not six independent agent implementations. Native STS is a
separate capability and is not being converted into this LLM response protocol.

The dependency lock records ReqLLM 1.29.0 and LLMDB 2026.10.6. Installed ReqLLM
Google code contains schema projection and object-plus-tools handling for Gemini
3 and later, including handling for `gemini-3.5-flash-lite`. Therefore the local
OpenAI-only gate is not evidence that the dependency lacks Google support.
Neither source inspection nor upstream documentation establishes successful live
behavior for the user's model through Vxpipe's entire request/history path.

Earlier implementation notes record malformed/fenced dialogue and unwanted tool
calls from Google candidates. They also record an invalid earlier test that
removed business tools during ordinary replies. Preserve those counterexamples;
do not rerun until a lucky response and call that acceptance.

## Proposed ownership and behavior

1. Agent Runtime owns one schema, prompt contract, parser, output bounds and
   typed dialogue result. Call Engine still owns whether speech or idle is
   admitted. User-authored prompts do not define or replace the response schema.
2. Every registered LLM integration uses this protocol. Adding an integration
   must not require adding a model ID to a structured-reply permission list.
   A new model ID alone cannot fail save/publish because it was not individually
   certified. Existing ordinary model existence, credentials, tools and option
   checks remain; upstream failures are reported truthfully.
3. The shared request contract always instructs JSON dialogue and validates the
   final response. Native schema enforcement is a transport enhancement, not
   an eligibility requirement. Use native schema plus native tools where the
   selected API supports that combination; otherwise use JSON mode or the shared
   instructed-JSON path with the identical strict decoder. Resolve the encoding
   strategy once for an activation from actual transport capabilities, not a
   hand-maintained model approval table. Unknown native capabilities select the
   portable path rather than forbidding the integration.
4. Keep the full authorized native tool declarations on ordinary, tool-result,
   async-completion and idle continuations. Do not force a synthetic
   `structured_output` function, disable tools to obtain JSON, turn prose into a
   fabricated valid reply, or silently switch to legacy behavior. Native tool
   dispatch remains owned by the existing executor.
5. Proposed bounded recovery: allow at most one correction request for a complete
   malformed dialogue result when that logical request has dispatched no tools,
   emitted no speech and remains within its original deadline/token budget.
   Preserve the selected provider/model/credential and request strategy. Keep
   repair context private and out of settled history. A repair that returns tools
   cannot dispatch them. Cancellation fences both attempts. Refusals, incomplete
   streams, transport failures and requests with any dispatched tool fail without
   this retry. Meter both attempts. This is not model/provider fallback, JSON
   patching, or a new unrestricted agent loop. Recheck the proposal against the
   existing request lifecycle before implementing it in checkpoint A.
6. Provider-specific code is limited to encoding and normalization: schema
   placement, native roles/tool blocks, finish/refusal signals and required
   reasoning/signature replay. No provider implements a different dialogue type
   or changes speaker/listener semantics. Reuse ReqLLM behavior where verified;
   do not fork six schema validators or invent six loops.
7. Preserve append-only logical history and provider-normalized prefixes. Retain
   exact tool IDs/results and necessary opaque metadata through continuation,
   interruption, recovery and compaction. Replay stays bounded, private and bound
   to the matching provider/model and canonical messages; never carry alternate
   unredacted text/arguments in metadata. Router changes must not replay opaque
   data into an incompatible downstream provider.
8. No raw JSON, partial fields, malformed output or metadata reaches TTS. Exhausted
   validation failures remain typed request failures, never successful silence.
   This is a universal integration contract, not a promise that every stochastic
   response or every upstream model feature is infallible.

## Compatibility and authoring

Keep the public call-spec shape and `mode_message_v1` semantic contract. Historical
legacy publications remain legacy; no blanket backfill or silent republish.
New saves and publication use the same validator without a model-name whitelist.
Unknown protocol versions still fail. Existing saved credentials and visibility
rules are unchanged; successful compilation does not require a live model call.

Review whether the strategy or recovery policy needs a versioned private snapshot
for reproducibility, using the existing publication/activation pinning mechanism.
Do not reuse a semantic version for incompatible dialogue behavior. Do not store
credentials in snapshots. Direct/standalone generated-history sessions and native
STS retain their explicit existing defaults.

The editor continues to show configured integrations by name. It must not hide a
configured LLM integration because it lacks a native JSON-schema feature. Remove
obsolete profile-only error text while preserving actionable errors for actual
invalid credentials/options/model identifiers. Save/publish failure must preserve
edits and must not create a revision.

## Alternatives rejected

- Removing only `supports_model?`: leaves OpenAI-specific options and replay in the
  shared path and can accept specs that fail on first inference.
- Adding Gemini or selected model IDs to the allowlist: contradicts the requirement
  and repeats the same breakage for future integrations and models.
- Requiring native strict JSON Schema everywhere: confuses the application
  contract with an optional upstream feature.
- Accepting any prose or extracting fenced JSON: weakens the existing validation
  boundary and can misinterpret control content.
- Forcing a schema tool or omitting business tools: changes the native tool
  contract and repeats the earlier invalid acceptance shortcut.
- Provider fallback or automatic legacy downgrade after failure: changes provider
  selection or protocol semantics without the author's choice.

## External evidence and limits

Primary documentation checked on 2026-11-18; these are API capabilities, not
Vxpipe acceptance results:

- [Google structured outputs](https://aistudio.google.com/docs/structured-output)
  documents JSON Schema and structured-output/tool combinations for newer Gemini
  generations. Verify the installed dependency's exact streaming request body.
- [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
  describes native schema enforcement. Preserve the working Responses path.
- [DeepSeek JSON output](https://api-docs.deepseek.com/guides/json_mode/) and
  [tool calls](https://api-docs.deepseek.com/guides/tool_calls/) describe distinct
  output/tool surfaces; [thinking mode](https://api-docs.deepseek.com/guides/thinking_mode/)
  requires particular continuation metadata. Validate their combination locally.
- [Fireworks structured outputs](https://docs.fireworks.ai/structured-responses/structured-response-formatting)
  describes JSON object and schema modes; this alone does not prove native tools
  remain available across Vxpipe's conversation.
- [OpenRouter structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs)
  documents capability-dependent routing. Route capability evidence must not
  become a Vxpipe model approval table.
- [Zenmux structured outputs](https://zenmux.ai/docs/guide/advanced/structured-output.html)
  documents protocol-specific schema surfaces. Test the configured native route
  rather than assuming OpenAI-format parameters work on every route.

No provider credentials were read and no live inference, runtime change or
production deployment was performed for this investigation.

## Implementation decisions — initial shared boundary

The first implementation slice deletes identity eligibility from plan pinning and
replaces DialogueProfile with shared option validation. Model resolution, credential
validation, protocol validation and idle-on-STS checks retain their owners. The
name `structured_output` is no longer reserved: the runtime consumes raw text and
never creates a synthetic schema tool.

ReqLLM configuration pins a private reply strategy alongside its immutable resolved
model. The initial strategies are OpenAI Responses schema encoding (selected from
ReqLLM's transport resolution) and portable instructed JSON for other transports.
Both retain the same decoder and native tools. Provider options such as Google
authentication and native routing survive projection; output/protocol overrides
and forced tools remain invalid. Native encoding for other transports follows in
the provider checkpoints. Legacy requests do not receive either modern overlay.

The Google checkpoint adds native object encoding when ReqLLM can prepare an
object request with the shared schema and a native tool. This is an offline SDK
probe, not inference or a model permission list; unsupported combinations keep
portable JSON. Configured Google Search/URL-context options also select portable
JSON because the SDK object encoder omits those builtins. Selection is fixed with
the configuration, including rounds without
tools. The native path retains raw text for the same strict decoder. Its exact-source
dependency patch preserves explicit output caps below 200 and suppresses Google's
SDK-generated schema tool chunk, while preserving actual native calls regardless
of their names. Buffered and streaming HTTP fixtures verify these boundaries.

OpenAI replay compatibility now checks the Responses transport independently of
reply eligibility. New replay records bind both catalog and actual wire model IDs;
older records default the wire ID to their recorded model ID. No opaque record may
cross a changed model or transport. This initial slice was followed by the Google, direct-chat and router replay
implementations described below.

The initial review identified two lifecycle constraints for bounded correction: output limits currently apply per attempt, and
legacy blocking acknowledgments deliberately omit tools. Correction requires
a finite trustworthy remaining output allowance; absence of one cannot authorize
an extra full-budget attempt. Modern full-tool acknowledgments retain legacy behavior separately. The resolved
policy and its implementation evidence follow below; full provider acceptance
continues in the milestone.

## Bounded correction policy — resolved before implementation

The private `bounded_once_v1` policy is pinned in the Session child specification,
with the selected provider configuration and transport strategy. It is an execution
policy for the existing valid dialogue contract, not a new public protocol or a
publication migration. Legacy snapshots retain legacy execution. Existing modern
snapshots continue to mean exactly the same valid mode/message result; correction
only gives invalid, effect-free output one bounded opportunity to satisfy it.
Unknown private policy versions fail configuration instead of silently changing it.

Correction runs inside the existing RequestRunner task and Session request token.
The original timer, cancellation and stale-result fence cover both attempts. It is
available only on the first model round, with no native submissions, after successful
provider normalization and `invalid_dialogue` from the final decoder. Refusal,
truncation, transport error, output overflow and any earlier submission cannot
trigger correction. A correction consumes the next model attempt/round; a one-round
limit disables it. There is never a third attempt or a separate tool executor.

A finite original output allowance is required. Pin the tighter available provider
output limit and configured compaction output reserve; submit that cap on the first
attempt. Subtract the reported first-attempt output-token usage before correction.
Require explicit `usage_reported.output == true` provenance, as well as an integer
count: normalized zero-fill or reasoning-only partial measurements do not establish
an allowance. Missing, contradictory, noninteger or exhausted output usage disables
correction. Absent provenance disables correction only, never integration admission.
The correction request receives only the remaining allowance, with the same byte
and stream-event bounds. Input must fit the pinned context window, reserving the
remaining output tokens, using the shared conservative input accounting plus the
complete dialogue instructions. Unknown context capacity or failed measurement
also disables correction. The policy does not claim a shared billing ceiling for
repeated input tokens: each attempt's actual input/output usage is emitted normally.

Build repair context from the already prepared request plus the malformed assistant
response (including compatible private replay) and a fixed correction instruction.
Do not fetch new context, compact, commit, or settle these private additions. Retain
the complete native tool declarations on the correction request, but reject any
returned tool calls before dispatch. Only a valid final dialogue can reach host
settlement. Malformed repair, repair tools and exhausted budgets remain typed
failures, never successful silence. Subsequent caller input sees neither malformed
output nor correction instructions.

Modern blocking-tool acknowledgments keep the complete authorized tool declarations,
like all other modern rounds, and still use the one existing executor and round
limit. Blocking controls conversation admission, not the schema transport's tools.
Legacy tool-less acknowledgments retain their existing behavior. Neither path may
repeat a previous side effect as part of correction.

The correction wire tests also established two integration-boundary fixes. Provider
option namespaces/maps are normalized through ReqLLM after strict validation, so
none can bypass the host-owned history/output checks. Applying a runtime output
cap removes conflicting native token aliases before encoding. Google buffered
chat required the [checked-in native-signature patch](../../patches/req_llm/README.md)
to retain upstream function-call signatures in subsequent tool-result requests.

### Google continuation records

Google signatures can belong to public text, private thinking, function calls or
empty streaming carriers. A reasoning-only record loses their original Part
layout. The Google replay adapter therefore stores an ordered layout: byte ranges
into canonical public text, indices into canonical tool calls, private thinking
text, and the original optional thought/signature attributes. Public text and
arguments are never copied into replay. Restoring requires complete, ordered,
non-overlapping coverage of public text and calls, including zero-length carriers.
A source digest binds the original text, call IDs, names, arguments and metadata;
provider, catalog model and wire model must also match. Unknown Part fields and
variants fail closed. The record and tool signatures share a 64 KiB bound.

The SDK's private typed Part records are consumed at normalization. Projection
reconstructs them from validated canonical source data so the encoder preserves
signed Part order and does not reclassify public text as private thinking. These
records never become speech, transcript content or summary text. Existing generic
history/compaction ownership remains unchanged.

ReqLLM's buffered object decoder and streaming response builder need reproducible
patches to preserve all Parts, including empty signature carriers. Native-ID
provenance is retained separately from runtime-generated dispatch IDs. Supplied
IDs are replayed and echoed in results; absent original IDs stay absent. Google's
[FunctionCall/FunctionResponse protocol](https://github.com/googleapis/googleapis/blob/master/google/ai/generativelanguage/v1beta/content.proto)
requires matching IDs when supplied, while its
[thought-signature guidance](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/thinking/thought-signatures)
requires preserving the signed Part's original placement. Encoding from references
rather than alternate public text preserves both constraints.

### Google reported-usage provenance

Live buffered/streamed comparison and local raw-HTTP reproduction showed an SDK
normalization asymmetry: buffered decoding lost output-reporting flags, while
streamed missing counts acquired flags from synthesized zeros. Preserve flags
from raw Google usage metadata before defaults are introduced. Explicit candidate
counts, with absent or valid reasoning counts, are reported output; total-minus-
input inference is not sufficient provenance for correction. Valid explicit zero
is distinct from missing zero. Reasoning remains part of consumed output tokens.

Rejected relaxing DialogueRepair to trust every numeric normalized counter: that
would authorize correction without a measured allowance. The shared policy stays
unchanged; unknown usage disables correction without rejecting the integration.
The cumulative SDK patch and all prior source-state upgrade paths carry the fix.
Focused wire tests verify bounded second-request caps and missing/malformed usage
rejection in native/portable buffered/streamed modes. Live acceptance remains
separately tracked in the retained evidence; this fix alone does not close B.

Stream provenance is final-event scoped: a previous reported output flag cannot
mask a missing final counter. Google also retains private raw candidate/reasoning
components for this check. If either final component decreases below a previously
reported component, correction is disabled; generic max-of-combined counters
could otherwise undercount consumed output. No inferred counter or fabricated
billing value is introduced. Normal increasing final components remain eligible.

### Affirmative native encoding evidence

Google native schema selection now requires affirmative resolved `json.schema`
capability metadata as well as successful SDK schema-plus-tools preparation.
Absent or false capability metadata selects the portable instructed/validated path;
it does not deny configuration, saving, publishing or the modern protocol. Existing
builtin-tool exclusions still preserve the portable encoder's full tool surface.
The chosen encoding remains pinned for the Session; there is no error-triggered
strategy switch or legacy fallback.

The earlier offline SDK probe alone established that a request could be encoded,
not affirmative support for that combination. Lack of affirmative metadata does
not prove the provider lacks schema support and does not establish the cause of
observed live tool loops. Tests supply explicit capability evidence to exercise
native encoding and cover replay in both strategies. No production model-ID list
or catalog exclusion is introduced.

## Reply envelope correction — 2026-11-18

The recorded DeepSeek streaming response copied the four-field participant
format already supplied in assistant history. Our two-field output schema and
repair instruction contradicted that example. The user explicitly directed us
to expect `type` and `participant_id` back, and rejected backward compatibility.
Modern replies therefore require exactly the four-field envelope. The original
two-field modern shape is rejected; this deliberately updates `mode_message_v1`
per that instruction. Explicit legacy unstructured operation is separate.

We rejected removing attribution from history because transfers and multi-agent
conversations need truthful speaker attribution, and rejected accepting both
shapes because the user requested one contract. We do not rewrite saved snapshots
or history. Current request instructions explicitly supersede older output-shape
instructions; newly captured prompts and native schemas request the same shape.
The activation supplies its own ID even before the first reply or after a transfer;
standalone sessions without an application-supplied ID use `agent`.

Returned identity never controls routing, permissions, admission or settlement.
The decoder validates and drops attribution before producing the typed dialogue;
the host stamps supported delivered speech with its own participant ID. Native
tools, private replay, usage accounting, deadlines and repair restrictions stay
owned by their existing boundaries. The older release candidate and live results
predate this correction and do not establish acceptance of this contract.
