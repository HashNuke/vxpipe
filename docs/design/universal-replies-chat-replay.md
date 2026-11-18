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

Host settlement deliberately replaces generated dialogue with actual spoken
history. Preserving reasoning for ordinary final answers across that boundary
must not replay unspoken output or attach source-bound signatures to edited text.
The direct tool-exchange fix does not resolve that separate lifecycle contract;
it remains a C acceptance requirement, alongside interruption and compaction.

OpenRouter's [reasoning guide](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
requires the original ordered sequence of reasoning detail blocks on continuation.
ReqLLM has a typed OpenRouter adapter, while its Zenmux buffered decoder currently
attaches raw maps and its generic streaming decoder normalizes them. The runtime
currently drops both providers' replay. Their implementation must reconcile those
representations and fence downstream-model/routing changes before C can close.

Run the focused regression from `apps/vxpipe_agent_runtime`:

```sh
mix test test/vxpipe/agent_runtime/provider/chat_reasoning_replay_test.exs
```

The initial four cases failed on the outgoing reasoning field; all four now pass,
including source/model tampering checks. Run `python3 test/shell/req_llm_patch_test.py`
from the root for fresh, repeated, previous-state and unknown-edit preparation
checks. Live acceptance for these providers remains pending; synthetic HTTP
responses establish encoding behavior, not upstream availability or compliance.
