# Universal reply conformance evidence

Updated on 2026-11-18 for the user-directed strict four-field reply correction. This distinguishes
exercised behavior from successful live acceptance. The
[milestone](../../labnotes/milestones/universal-agent-replies.md) remains incomplete;
no deployment is claimed. Zenmux live acceptance is deferred by explicit user
direction, not reported as passed.

## Integration matrix

| Integration and live model | Selected reply encoding | Deterministic evidence | Latest applicable live result |
| --- | --- | --- | --- |
| Google AI Studio `gemini-3.5-flash-lite` | Portable instructed JSON for configured metadata; native schema with affirmative capability evidence | Both encodings and both modes; ordered Parts/signatures; exact native call/result pairing | `envelope-primary1`: configured buffered/streamed conversations pass; `envelope-room1`: real Hangup and Chrome/TTS call pass. Prior editor publication remains verified. |
| OpenAI `gpt-6-luna` | Native Responses schema | Both modes; strict schema and full tools; source/model-bound replay | `envelope-primary1`: configured buffered/streamed conversations pass; `envelope-room1`: real Hangup and Chrome/TTS call pass. Prior editor publication remains verified. |
| DeepSeek `deepseek-flash` | Portable instructed JSON | Both modes; unsigned reasoning replay and exact full-speech settlement | `envelope1`: buffered and streaming full conversations pass after fixing our reply/history inconsistency. |
| Fireworks `accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b` | Portable instructed JSON | Both modes; reasoning replay, usage provenance and settlement | `envelope1`: buffered and streaming full conversations pass with unchanged semantic assertions. |
| OpenRouter `google/gemini-3.5-flash-lite` | Portable instructed JSON | Both modes; raw reasoning details, reported-model provenance and pinned continuation routing | `envelope1`: buffered and streaming full conversations pass, including the required native lookup. |
| Zenmux `openai/gpt-4o` | Portable instructed JSON | Both modes; raw reasoning details and model-bound continuation; same terminal matrix | Live deferred. Missing credential attempt retained; no successful live result claimed. |

Native encoding is a transport choice, not protocol eligibility. All six use the
same strict `Dialogue` decoder. The terminal matrix is registry-checked and covers
speaker, cue, null silence, duplicate keys, unknown mode, invalid speaker/null,
four-field envelopes, missing attribution, invalid type, malformed/oversized text, refusal and truncation through actual local HTTP and
public Session admission: **157 tests pass**. It also checks exact failure reasons,
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
| `envelope1` | 6 | 0 | User-directed four-field contract consistent with history; same models, cap, tools and semantic assertions |

The five earlier heterogeneous runs contain 14 passes in 30 cases, including
four configuration failures. They are not a model reliability estimate.
`envelope1` is a separate, fixed six-case run after a concrete implementation
correction. All six full conversations pass; 60 step metrics are retained. No
acceptance waiver, weakened semantic assertion or automatic retry was used.

The prior DeepSeek rejection exposed our inconsistent reply/history formats.
The decoder previously rejected a valid participant envelope we had shown the
model in assistant history. That diagnosis is corrected below; historical logs
remain intact. The prior Fireworks and OpenRouter semantic failures are also
retained, without treating a single passing run as a reliability guarantee.

## Reply-envelope correction supersedes the earlier diagnosis

The user identified that our assistant history already used type/participant_id.
DeepSeek's `remaining4` response copied that format, while our decoder expected
only mode/message. The user directed one strict four-field reply contract. The
earlier result remains a historical failed run but is not evidence that DeepSeek
was wrong to mirror our own history. All ten configured runtime conversations and all four refreshed real Hangup/Chrome
cases pass. The updated candidate image audit is independently clean; root verification
passes 5,892 tests, zero failures, 409 excluded (seed 914326). The earlier candidate predates this change.

The refreshed `envelope-room1` run passes all four cases: two real Hangup actions
and two Chrome/Deepgram-TTS conversations. Both desktop and phone captures were
inspected. The full transcript/speech matching assertions and Google tool-mode
guard executed in this run (unlike the historical browser2 follow-up).
