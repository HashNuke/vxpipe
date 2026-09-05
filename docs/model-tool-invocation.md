# Model tool invocation

Status: Implemented bounded vertical slice

## Decision

Vxpipe owns model-requested tools as call-engine resources. Trusted application
configuration supplies tool modules; each module publishes a provider-neutral
name, description, JSON parameter schema, and execution callback. Client
protocols cannot provide callback modules or choose arbitrary executable names.

The first configured tool is `get_current_time`. It accepts no arguments and
returns the current UTC timestamp. It is intentionally local and credential-free
so the complete lifecycle can be exercised before adding HTTP actions or
business integrations.

## Runtime flow

```text
participant        room       model capability      provider       tool
    | SendText       |               |                  |             |
    |--------------->|-------------->| model request    |             |
    |                |               |----------------->|             |
    |                |               | tool call        |             |
    |                | tool started  |<-----------------|             |
    |                |<--------------| execute                        |
    |                |               |------------------------------->|
    |                | tool stopped  | result                         |
    |                |<--------------|<-------------------------------|
    |                |               | continuation     |             |
    |                |               |----------------->|             |
    |                | text/speech   | final answer     |             |
    |<---------------|<--------------|<-----------------|             |
```

The entire model/tool/model loop runs inside the model capability's existing
supervised request task. The room authority therefore never executes a tool or
waits on provider I/O. The original request timeout bounds all tool rounds and
provider continuations together. Immediate typed input or provider-confirmed
speech interruption kills that task, clears queued work, and follows the normal
agent-turn cancellation path.

Tool rounds are explicitly bounded. The development configuration permits two;
reaching the bound fails the agent turn instead of allowing an uncooperative
model to loop indefinitely. Tool results must be JSON-compatible and fit the
configured byte limit before they can be returned to the model.

## Provider boundary

The model provider behavior receives neutral tool definitions alongside neutral
conversation messages. It may return final text or a list of normalized tool
calls. The capability executes those calls and appends one neutral assistant
tool-call message plus the corresponding tool-result messages before asking the
provider to continue.

ReqLLM translates the definitions and messages into its provider-facing types
and classifies both buffered and streamed responses. Provider continuation
metadata, including metadata required by some models to replay a tool call, is
retained as opaque adapter state. It is restored on the continuation request but
is never copied into room events or RTVI messages.

Successful history continues to store the originating user text and final
assistant answer as one pair. Intermediate calls and results are available during
the live model loop but are not yet durable conversation history.

## Events and RTVI projection

Room authority publishes sequenced, protocol-neutral `ToolCallStarted`,
`ToolCallCompleted`, `ToolCallFailed`, and `ToolCallCancelled` events. They carry
the agent participant, originating participant and connection, command and
correlation IDs, and tool-call identity. Public events contain validated
arguments or bounded results, never executable modules or provider metadata.

The RTVI gateway projects these as the standard 2.1 events:

- `llm-function-call-in-progress` when execution begins;
- `llm-function-call-stopped` with `cancelled: false` for success or failure; and
- `llm-function-call-stopped` with `cancelled: true` when the owning turn is
  interrupted.

An interrupted room turn records its active call IDs and emits their cancellation
events before `bot-interrupted`. Late completion messages from a cancelled task
are ignored because the owning agent turn no longer exists.

## Configuration

The development model settings include:

```elixir
tools: [Vxpipe.CallEngine.Tool.CurrentTime],
maximum_tool_result_bytes: 16_384,
maximum_tool_rounds: 2
```

An embedding application may configure its own modules implementing
`Vxpipe.CallEngine.Tool`. These modules receive an engine-owned context with the
tenant, room incarnation, participants, connection, command, and correlation
identity. Tool authorization should be implemented against that trusted context,
not arguments supplied by the model.

## Alternatives rejected

- Provider-owned automatic execution would bypass engine authorization,
  lifecycle events, interruption, and result limits.
- Client-executed tools would move trusted work into a protocol-specific browser
  path and make authenticated participant attribution harder.
- Calling tools in room authority would block room sequencing on application or
  network latency.
- Starting with a webhook tool would mix the core lifecycle with outbound
  credentials, retry, and idempotency design.
- Unbounded tool rounds could consume provider requests indefinitely.

## Deferred work

This slice executes calls sequentially within one supervised request task.
Independent per-tool processes, parallel tool calls, tool-specific timeouts,
approval gates, durable call/result history, idempotency keys, redacted RTVI
reporting levels, and HTTP/webhook tools remain later slices.

## Verification evidence

- Executor tests cover configured execution, JSON/size validation, invalid
  arguments, unknown names, and duplicate definitions.
- Model-capability tests cover tool discovery, execution, neutral result
  continuation, and a final answer in the original turn.
- Room integration tests cover sequenced start/completion events and prove a
  blocking tool is killed and publicly cancelled before turn interruption.
- ReqLLM tests cover tool schema translation, assistant/tool continuation
  messages, and opaque provider metadata preservation.
- Gateway codec tests cover successful and cancelled RTVI lifecycle payloads.
- Manual samples steps are maintained in `samples/README.md` and the associated
  implementation labnote.
