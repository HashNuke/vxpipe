# Universal reply conformance evidence

Recorded on 2026-11-18 for the implementation through `bde23c93`. This distinguishes
exercised behavior from successful live acceptance. The
[milestone](../../labnotes/milestones/universal-agent-replies.md) remains incomplete;
no deployment is claimed. Zenmux live acceptance is deferred by explicit user
direction, not reported as passed.

## Integration matrix

| Integration and live model | Selected reply encoding | Deterministic evidence | Latest applicable live result |
| --- | --- | --- | --- |
| Google AI Studio `gemini-3.5-flash-lite` | Portable instructed JSON for configured metadata; native schema with affirmative capability evidence | Both encodings and both modes; ordered Parts/signatures; exact native call/result pairing | `resume1`: configured and explicit portable conversations pass in both modes. `browser2`: editor publication and real Chrome/TTS call pass. |
| OpenAI `gpt-6-luna` | Native Responses schema | Both modes; strict schema and full tools; source/model-bound replay | `resume1`: both modes pass. `browser2`: editor publication and real Chrome/TTS call pass. |
| DeepSeek `deepseek-flash` | Portable instructed JSON | Both modes; unsigned reasoning replay and exact full-speech settlement | `remaining4`: buffered passes; streaming post-tool extra fields rejected. Earlier streaming success is historical. |
| Fireworks `accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b` | Portable instructed JSON | Both modes; reasoning replay, usage provenance and settlement | `remaining4`: buffered passes; streaming correction returns valid dialogue with the wrong arithmetic answer. Earlier streaming success is historical. |
| OpenRouter `google/gemini-3.5-flash-lite` | Portable instructed JSON | Both modes; raw reasoning details, reported-model provenance and pinned continuation routing | `remaining4`: buffered passes; streaming acknowledgment occurs without required native lookup submission. Earlier streaming success is historical. |
| Zenmux `openai/gpt-4o` | Portable instructed JSON | Both modes; raw reasoning details and model-bound continuation; same terminal matrix | Live deferred. Missing credential attempt retained; no successful live result claimed. |

Native encoding is a transport choice, not protocol eligibility. All six use the
same strict `Dialogue` decoder. The terminal matrix is registry-checked and covers
speaker, cue, null silence, duplicate keys, unknown mode, invalid speaker/null,
malformed/oversized text, refusal and truncation through actual local HTTP and
public Session admission: **121 tests pass**. It also checks exact failure reasons,
no public raw-text delta/result, and one HTTP request. Zenmux participates fully.

## Tools, history and lifecycle evidence

Live step metrics alone do not prove wire shape or immutable history. These
permanent deterministic suites provide the corresponding evidence under
`apps/vxpipe_agent_runtime/test/vxpipe/agent_runtime/`:

| Property | Owning tests |
| --- | --- |
| Actual schema placement, complete native tools and optional Google tool choice | `provider/openai_dialogue_wire_test.exs`, `provider/google_dialogue_wire_test.exs`, `provider/dialogue_repair_wire_test.exs` |
| All-six private replay, original tool IDs/results and provider-normalized continuation | `provider/req_llm_replay_test.exs`, `provider/google_replay_wire_test.exs`, `provider/chat_reasoning_replay_test.exs`, `provider/router_replay_wire_test.exs` |
| Router model/configuration mismatch rejection, no synthetic calls from quoted reasoning | `provider/router_replay_wire_test.exs`, `provider/router_native_call_test.exs` |
| Bounded correction, actual usage, no correction-side tool dispatch or post-dispatch retry | `dialogue_repair_test.exs`, `provider/chat_usage_repair_test.exs`, `provider/google_usage_repair_test.exs`, `provider/dialogue_repair_wire_test.exs` |
| Settlement, cancellation, recovery, protected compaction tail and no repeated effects | `pending_reply_replay_test.exs`, `settled_reasoning_replay_test.exs`, `replay_lifecycle_test.exs` |
| Refusal provenance through buffered and fragmented streamed decoding | `provider/chat_refusal_wire_test.exs`, `provider/universal_terminal_wire_test.exs` |

Shared Session tests exercise ordinary and engine-origin inputs, async/idle
continuations, strict buffering, cancellation and deadlines. Call Engine's
`agent_runtime/tool_conversation_room_test.exs` and `idle_room_test.exs` cover
actual modern executor/async completion and idle lifecycle. These shared lifecycle
checks compose with the transport matrix; this is not a claim that every lifecycle
transition has six duplicate implementations or six duplicate tests.

The browser call checks retain full tool declarations and verify real lookup
completion, unrelated input, spoken/silent idle expiry and audio. Captured overall,
per-case and timeline transcript text matches actual TTS input. The Google optional
mode guard was added after `browser2`; deterministic encoded HTTP verifies that
property, not a retroactive claim about the live assertion. Google/OpenAI controlled
published rooms also exercised the real Hangup action and monitored teardown.

## Retained attempts and limits

The [fixed plans](universal-replies-live-plan.md) precede their corresponding
executions. The [machine-readable evidence](universal-replies-live-evidence.json)
retains failures as well as successes, per-step elapsed time, reported token usage,
model-attempt counts, selected encoding and semantic outcomes. Earlier completed
rows whose semantic assertions were weaker are not retroactively treated as
passing the stricter current scenario.

For the remaining-provider fixed runs:

| Run | Cases | Failures | Material difference |
| --- | ---: | ---: | --- |
| `remaining1` | 6 | 2 | 2,048-token budget; before buffered usage correction |
| `remaining2` | 6 | 3 | Buffered usage correction; two Fireworks reasoning-length failures |
| `remaining3a` | 6 | 4 | Invalid 8,192-token fixture cap rejects both Fireworks cases before HTTP |
| `remaining3b` | 6 | 4 | Second preplanned repetition; same fixture-cap rejection |
| `remaining4` | 6 | 3 | Validated 4,096-token cap and reviewed lifecycle/refusal implementation |

These heterogeneous runs contain 14 passes in 30 cases, including four
configuration failures. They are not a model reliability estimate and cannot be
combined into one clean current-revision acceptance run. The latest three streamed
scenarios remain failing acceptance under the existing milestone policy. Historical
streamed passes precede usage/lifecycle/budget changes. No automatic retry-until-green
or weakened semantic assertion is used to close that gap.

The latest failures demonstrate three distinct outcomes: invalid post-tool JSON is
rejected without repeating the tool; a valid reply can be semantically wrong; and
a model can acknowledge a tool without calling it. They do not establish a new
runtime invariant violation. A model's stochastic behavior is not guaranteed by
protocol admission. Release policy must nevertheless honor the milestone's
explicit acceptance requirements unless the user changes them.
