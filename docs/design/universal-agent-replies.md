# Universal structured replies for LLM integrations

Status: implementation in progress, 2026-11-18; shared eligibility and portable
projection are implemented, while recovery and full provider acceptance remain open.
The user's requirement is definitive: remove the structured-reply allowlist and
support the shared agent response contract across every LLM integration.
Implementation details below are the proposed design, not completed behavior.

Implementation owner: [milestone](../../labnotes/milestones/universal-agent-replies.md).
Research evidence: [labnotes](../../labnotes/20261118-1435-universal-agent-replies.md).
This supersedes the OpenAI-only eligibility policy in the
[structured-message design](structured-agent-messages.md), not its message,
history, tool, privacy, settlement or idle contracts.

## Findings

The common response already exists in `Vxpipe.AgentRuntime.Dialogue`: exactly
`agent_mode` and `message`, with listener/null, listener/text and speaker/text
allowed. Duplicate keys, extra fields, blank text and speaker/null are rejected.
RequestRunner buffers modern replies and decodes the complete final result before
speech admission. Native tool rounds remain distinct from dialogue.

The restriction is introduced at several boundaries:

| Boundary | Current implementation | Required change |
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
name `structured_output` is no longer reserved: the runtime uses text output and
never creates a synthetic schema tool.

ReqLLM configuration pins a private reply strategy alongside its immutable resolved
model. The initial strategies are OpenAI Responses schema encoding (selected from
ReqLLM's transport resolution) and portable instructed JSON for other transports.
Both retain the same decoder and native tools. Provider options such as Google
authentication and native routing survive projection; output/protocol overrides
and forced tools remain invalid. Native encoding for other transports follows in
the provider checkpoints. Legacy requests do not receive either modern overlay.

OpenAI replay compatibility now checks the Responses transport independently of
reply eligibility. New replay records bind both catalog and actual wire model IDs;
older records default the wire ID to their recorded model ID. No opaque record may
cross a changed model or transport. This does not yet implement other providers'
opaque continuation records.

Before bounded correction is implemented, its remaining policy work must address
two observed lifecycle constraints: output limits currently apply per attempt, and
legacy blocking acknowledgments deliberately omit tools. Correction will require
a finite trustworthy remaining output allowance; absence of one cannot authorize
an extra full-budget attempt. Modern full-tool acknowledgments must be specified
and tested separately while retaining the legacy behavior. The milestone remains
open until these contracts and their cancellation/history evidence are complete.
