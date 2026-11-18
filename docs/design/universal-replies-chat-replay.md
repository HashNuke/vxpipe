# Chat Completions reasoning replay

This is checkpoint C's transport investigation and incremental implementation
record for universal replies. It does not establish completion of C or the live
acceptance matrix. ReqLLM is pinned at 1.29.0.

## Direct transports

DeepSeek and Fireworks return private reasoning in `reasoning_content`. Retain it
in the existing bounded private replay field and restore SDK thinking parts when
projecting the original native assistant exchange. Do not insert reasoning into
public text, speech, summaries or tool arguments. The codec binds provider,
configured model, wire model, public text and complete canonical native calls.
Changed source content or calls, incompatible models, extra envelope fields and
oversized replay fail before an outgoing request.

The SDK represents buffered reasoning as thinking content. Its streamed builder
also synthesizes typed `openai-reasoning-content-v1` records per thinking chunk.
Accept only a contiguous ordered sequence whose joined text exactly duplicates
the thinking content and carries no signature or additional provider data.
Unknown private layouts fail instead of being silently
discarded. This codec does not claim to support routed OpenRouter/Zenmux details.

The shared real-HTTP regression covers DeepSeek and Fireworks in buffered and
streamed modes with all native tools present. Before the fix, DeepSeek's second
request contained an empty reasoning string; Fireworks omitted the field. The
runtime lost the content during normalization. Additionally ReqLLM's Fireworks
encoder explicitly stripped it. The cumulative checksum-pinned dependency patch
now retains `reasoning_content` while still stripping unsupported message metadata
and OpenRouter-shaped `reasoning_details`. All previously prepared source states
remain supported by exact-state upgrades.

The [DeepSeek thinking guide](https://api-docs.deepseek.com/guides/thinking_mode/)
requires prior reasoning when requests carry tools, including previous turns with
no tool calls. The [Fireworks reasoning guide](https://docs.fireworks.ai/guides/reasoning)
requires reasoning on interleaved tool continuations and documents preserved
thinking across user turns. Both were checked on 2026-11-18. These are wire
contracts, not grounds for a provider/model admission list.

## Rejected alternatives

- Empty or omitted reasoning is not equivalent to retaining native exchanges.
- Putting reasoning into dialogue text leaks private protocol data and violates
  the speech/history contract.
- Passing arbitrary SDK structs into persisted replay bypasses its JSON bounds
  and loses explicit compatibility checks.
- Removing all Fireworks field filtering would also expose unrelated unsupported
  fields. Change only the demonstrated reasoning loss.
- Treating every Chat Completions endpoint as identical would incorrectly assume
  direct-model reasoning rules cover router signatures and fallback models.

## Remaining decisions and verification

### Router affinity decision

Preserve ordinary configured routing until a response contributes private replay.
Record the explicit returned model with the exact raw ordered reasoning details,
canonical source binding and a digest of the original generation options. Missing
or contradictory returned-model provenance cannot authorize opaque replay.

Before every subsequent request, all retained router replay records must agree
on that model. Project the request to that model and disable alternate-model
routing/fallback while retaining the user's other provider settings. This applies
to later user turns too, for as long as private history is actually projected.
Release the restriction only when no such replay remains. Conflicting origins or
changed configuration fail before HTTP. A response contradicting an existing
affinity fails before further native tool dispatch. No saved spec, configuration
or ordinary reply strategy is mutated.

This deliberately narrows per-request fallback to preserve the native conversation;
checking a new response's model after sending the old blob would be too late.
OpenRouter's alternate-model list and route options must not survive into this
projection. Zenmux's model-routing configuration must not survive, and its native
provider fallback must be the documented string `"false"`. Verify actual encoded
requests and request counts, including original first-round routing, conflicting
history, missing provenance and subsequent ordinary caller input.

This is model affinity, not an inferred endpoint-identity permission gate. Provider
display names are not endpoint slugs, and format equality alone is not a proof of
signature compatibility. No general same-model endpoint incompatibility was
reproduced in the design review. Any additional compatibility constraint needs
provider evidence rather than a guessed identity mapping. The earlier native
fallback contract remains unchanged when no private replay is sent.

Sources: [OpenRouter model fallback](https://openrouter.ai/docs/guides/routing/model-fallbacks),
[Zenmux fallback](https://zenmux.ai/docs/guide/advanced/fallback.html), and
[Zenmux Chat Completion API](https://zenmux.ai/docs/api/openai/create-chat-completion.html).
Independent Astra xhigh design review identified both pre-request affinity and
its lifetime over all retained private history; implementation acceptance follows
the wire tests and remains open.

Host settlement deliberately replaces generated dialogue with actual spoken
history. Preserving reasoning for ordinary final answers across that boundary
must not replay unspoken output or attach source-bound signatures to edited text.
The direct tool-exchange fix does not resolve that separate lifecycle contract;
it remains a C acceptance requirement, alongside interruption and compaction.

OpenRouter's [reasoning guide](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
requires the original ordered sequence of reasoning detail blocks on continuation.
ReqLLM originally normalized OpenRouter fields differently from Zenmux and omitted
the returned model from streamed responses. The patch now preserves ordered raw
detail maps, including explicit null/empty fields, and records consistent explicit
model provenance from buffered responses or stream events. Missing, contradictory
or blank model provenance cannot authorize private replay. The runtime stores
bounded raw details and plain reasoning with source/configuration binding, then
projects the retained origin as described above.

Malformed present private fields must not disappear during decoding. The patch
retains a bounded invalid marker for non-null, wrongly typed reasoning fields;
the runtime rejects malformed known reasoning payloads before tool admission.
Redundant buffered reattachment was removed because it could overwrite an invalid
marker when another field contained a valid details array. Required known payload
types are checked without rebuilding the original maps or dropping opaque extras.

The buffered SDK also parsed quoted DeepSeek tool syntax inside private reasoning,
overwriting genuine native calls or creating calls that were never submitted by
the model's native tool channel. Modern router requests set the runtime-owned
`vxpipe_native_tool_calls_only` SDK option to disable this heuristic. It is absent
from the HTTP body; external modern option overrides are rejected. Legacy decoding
retains its prior default. Buffered/streamed native and no-native controls prove
that private reasoning cannot become speech or executable calls.

Current deterministic evidence: 32 focused real-HTTP cases pass, including exact
raw replay, cross-model affinity through later user input, conflicting origins,
source/options changes, malformed fields, quoted tool syntax and blank origins.
The shared conversation provider list is checked against the installed registry;
newly registered LLM integrations cannot silently omit conversation coverage.

Transport evidence uses ReqLLM 1.29.0 plus the pinned repository patch. Model names
below identify fixtures and live selections, not production permission entries.

| Integration | Model evidence | Submitted path | Current live evidence |
| --- | --- | --- | --- |
| Google AI Studio | `gemini-3.5-flash-lite` | Native schema and portable JSON locally; configured portable live | Both modes pass |
| OpenAI | `gpt-6-luna` | Native Responses schema | Both modes pass |
| DeepSeek | `deepseek-flash` | Portable JSON, Chat Completions, both modes | Streaming passes; buffered cue failed |
| Fireworks | `accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b` | Portable JSON, Chat Completions, both modes | Streaming passes; buffered extra-key reply failed |
| OpenRouter | `google/gemini-3.5-flash-lite` | Portable JSON, Chat Completions, both modes | Both modes pass |
| Zenmux | `google/gemini-3.5-flash-lite` local routed fixtures; `openai/gpt-4o` configured live selection | Portable JSON, Chat Completions, both modes locally | Deferred by user; no live HTTP request made |

Synthetic `other/model`/`third/model` responses exercise origin changes without
catalog allowlisting. No JSON-mode-only path is claimed. Native schema support is
optional: the four Chat Completions integrations use the shared instructed path
with native tools; the strict shared decoder owns acceptance in every case.

The first remaining-provider live run passed DeepSeek streaming, Fireworks
streaming and both OpenRouter conversations. Fireworks buffered failed on extra
dialogue keys; DeepSeek buffered returned silence when a listener cue was requested.
Both failures remain in the evidence. Zenmux's missing credential was reported and
the user explicitly deferred its live checks; deterministic coverage remains.

Run the focused regression from `apps/vxpipe_agent_runtime`:

```sh
mix test test/vxpipe/agent_runtime/provider/chat_reasoning_replay_test.exs
```

The initial four cases failed on the outgoing reasoning field; all four now pass,
including source/model tampering checks. Run `python3 test/shell/req_llm_patch_test.py`
from the root for fresh, repeated, previous-state and unknown-edit preparation
checks. Live acceptance for these providers remains pending; synthetic HTTP
responses establish encoding behavior, not upstream availability or compliance.
