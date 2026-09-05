# Model tool invocation

## Goal

Implement one complete, provider-neutral model tool loop:

```text
participant input -> model tool request -> supervised tool execution
                  -> model continuation -> streamed text and speech
```

The development samples path must expose enough standard RTVI lifecycle events
to observe the tool call and provide a simple manual test.

## Initial findings

- Model inference already owns one bounded supervised task per logical turn,
  streaming sentence output and cancellation inside that task. The smallest safe
  tool executor can run inside this task: room authority remains unblocked and
  existing interruption/timeout kills both provider continuation and tool work.
- ReqLLM classifies both buffered and streamed responses as either final text or
  tool calls. Its stream processor provides incremental text callbacks and a
  terminal response containing reconstructed tool calls.
- RTVI 2.1 defines `llm-function-call-in-progress` and
  `llm-function-call-stopped`. The samples console already logs standard RTVI
  events, so the gateway can project engine events without adding custom UI.
- Current conversation history stores successful user/final-assistant pairs.
  Tool-call and tool-result messages are needed during one request loop, but the
  first slice can retain the existing final-answer history contract.

## Plan

1. Define engine-owned tool definitions, calls, results, and an execution
   behavior. Add one argument-free `get_current_time` development tool.
2. Extend the provider-neutral model boundary to return tool calls and accept
   assistant/tool continuation messages. Keep streamed and buffered provider
   paths at parity.
3. Teach model inference to execute a bounded number of tool rounds inside its
   already supervised request task, emit lifecycle notifications, pass results
   back to the provider, and produce the normal final answer. Unknown, invalid,
   failing, timed-out, and interrupted calls must settle without crashing the
   room.
4. Add protocol-neutral room events and project them as the standard RTVI 2.1
   function-call lifecycle. Track active calls per agent turn so interruption
   emits cancellation before the turn interruption.
5. Configure the development agent with `get_current_time`, document the design
   in `docs/`, and add exact browser steps to `samples/README.md`.
6. Run focused tests at each boundary followed by all repository completion
   checks.

## Decisions

- Tool modules and definitions belong to the call engine, not RTVI or ReqLLM.
  Provider adapters translate schemas and conversation messages.
- Tools are trusted application configuration. Browsers cannot provide callback
  modules, schemas, or executable names when creating a room.
- The entire model/tool/model loop shares the original turn timeout and
  cancellation task. Per-tool worker processes and parallel calls can be added
  when a real tool needs independent lifecycle or concurrency.
- Tool rounds are explicitly bounded to prevent an uncooperative model from
  looping forever.
- We expose tool arguments/results in the development RTVI projection because
  the sample tool contains no secrets. A future authorization policy must support
  redacted reporting levels before sensitive tools are enabled.

## Rejected for this slice

- Client-executed tools: they weaken server authorization and do not exercise
  OTP-owned execution.
- An HTTP webhook tool: it adds external reliability and credential questions
  before the lifecycle itself is proven.
- Provider-owned automatic tool execution: it would bypass engine events,
  cancellation policy, and future authorization.
- Parallel tools: useful later, but unnecessary for the first complete loop.

## Manual samples acceptance test

These steps are the user-visible completion criterion and must be rerun after the
implementation is green:

1. Put valid `GEMINI_API_KEY` and `DEEPGRAM_API_KEY` values in the repository
   root `.env` and run `bin/dev`.
2. Open `https://<this-machine's-tailscale-fqdn>:5173/`, choose **Create room**,
   and then choose **Connect** in the voice console.
3. Type or say: “Use the get_current_time tool and tell me the current UTC time.”
4. In the console event log, verify one
   `llm-function-call-in-progress` event names `get_current_time`, followed by one
   `llm-function-call-stopped` event with `cancelled: false`.
5. Verify the assistant then displays and speaks a UTC time. The answer must come
   after the stopped event and remain one assistant turn.
6. Start the request again and immediately type another message with normal
   immediate-send behavior. Verify the tool/agent turn is interrupted, no stale
   answer arrives, and the replacement turn responds normally.

The exact event payloads and interruption behavior remain provisional until the
corresponding tests and live run are complete.

## Progress

- Created the running labnote and verified the existing provider, room, gateway,
  RTVI, and samples boundaries.
- Added the initial manual samples acceptance checklist before implementation.
- Added the engine-owned tool behavior, definition/call/context values, validated
  registry/executor, and the argument-free UTC clock tool. Executor output must be
  JSON-compatible and size-bounded. Focused tests cover successful execution,
  unknown names, invalid arguments, and duplicate configuration.
- Extended the neutral model provider contract with tool definitions, calls, and
  assistant/tool continuation messages. Model inference now performs at most the
  configured number of tool rounds inside the original supervised request task,
  returns failures to the model as tool results, and retains the existing final
  answer history contract.
- ReqLLM now translates tool schemas and continuation messages and classifies both
  streamed and buffered responses into final answers or engine tool calls.
- Added sequenced room events for tool start, success, failure, and cancellation.
  Active call IDs live with their agent turn; interruption cancels the supervised
  task and publishes tool cancellation before the turn-interrupted event.
- The gateway projects the lifecycle as RTVI 2.1
  `llm-function-call-in-progress` and `llm-function-call-stopped` events.
- Focused and application suites pass: 64 call-engine tests and 37 gateway tests,
  with existing network integration lanes excluded.
- ReqLLM classification normalizes calls before returning them. Those maps can
  contain provider continuation metadata such as a Gemini thought signature.
  The neutral call value now retains that metadata as an opaque adapter field;
  ReqLLM restores it on the assistant continuation message, while room events
  expose only the validated call ID, name, and arguments.
