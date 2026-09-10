# Tool execution model

Date: 2026-09-10. Status: selected target; ordered loop, cancellation-safe commit barrier,
private continuation admission, and room-level blocking/non-blocking tool flow implemented.

## Decision

Every model-requested Vxpipe tool invocation is always handed off to a bounded,
independently supervised Call Engine worker, regardless of tool kind or conversation mode.
The Agent Runtime request worker validates and resolves the request, but neither it nor an
agent/runtime GenServer ever executes the tool operation inline. This rule applies to
platform/built-in tools, Call Variables tools, host tools, and remote MCP tools.

Tool bindings have a separate conversation mode:

- `blocking` is the default. After the current post-submission acknowledgement finishes,
  later caller turns do not enter the LLM until that invocation's terminal observation has
  been consumed by the agent.
- `non_blocking` permits later caller turns while the invocation runs. Every such model
  request still contains the committed correlated running acknowledgement, so the LLM knows
  which work remains pending.

| Authored `conversation_mode` | Worker execution | Later caller turns while pending |
| --- | --- | --- |
| omitted | independent supervised worker | blocked |
| `blocking` | independent supervised worker | blocked |
| `non_blocking` | independent supervised worker | admitted |

There is no inline execution alternative behind this setting. `conversation_mode` changes
only Call Engine conversation admission after submission; it does not change how or where the
operation runs.

## Call-definition shape

Conversation mode belongs to the agent's local tool binding because two agents may use the
same underlying operation with different conversational behavior. Each authored platform/
built-in, host, or MCP binding obtains its tool-specific mode from that entry in the call
definition's participant `tools` map. Omission defaults to `blocking`; only the exception
needs to be authored:

```json
{
  "participants": {
    "reception": {
      "type": "agent",
      "tools": {
        "check_balance": {
          "type": "mcp",
          "integration": "banking",
          "tool": "get_balance"
        },
        "fetch_usage_rules": {
          "type": "mcp",
          "integration": "banking",
          "tool": "get_credit_card_rules",
          "conversation_mode": "non_blocking"
        },
        "end_call": {
          "type": "platform",
          "tool": "hangup"
        }
      }
    }
  }
}
```

The compiler accepts only `blocking` and `non_blocking`, resolves omission to `blocking`,
and pins the value in the immutable participant tool binding. It is private conversation
admission policy, not a model-selectable tool argument or client override. The setting does
not change worker placement, tool authorization, timeout, retry, visibility, or retention
policy.

The current dated compiler implements this field for explicitly authored host and MCP
selections. Permission-derived Call Variables tools compile with the default `blocking` mode.
The `platform` entry above records the approved unified-map target; selecting authored platform
tools through that entry still requires a later compiler checkpoint.

## Submission and conversation flow

1. A complete model tool call is assembled. Agent Runtime resolves its exact string name,
   validates its arguments against the pinned schema, and asks the Call Engine executor to
   submit it with the provider call ID as its invocation ID.
2. Call Engine performs authorization and capacity checks, then starts a temporary worker
   under the active agent's bounded invocation supervisor. Only successful worker startup
   returns an accepted submission. The admission request carries an absolute local deadline:
   if a busy registry handles it after the caller's bounded wait has expired, it rejects the
   queued request without starting work. If startup committed before the reply was lost, one
   bounded reconciliation reads that existing invocation instead of submitting it again.
3. Agent Runtime commits the assistant tool-call message and exactly one ordinary tool result:

   ```json
   {"status":"running","invocation_id":"call_123"}
   ```

   This is acknowledgement of accepted execution, not business success.
4. The same model request may perform one post-submission model round so the agent can tell
   the caller that work has started. If any accepted call is `blocking`, tools are withheld
   from that acknowledgement round: it may produce text, but cannot start more work before
   the blocking invocation completes.
5. A non-blocking invocation leaves later caller-turn admission open. The committed tool call
   and running result are included in every later model request. Before each provider
   generation, Agent Runtime also obtains a bounded current pending-invocation projection from
   Call Engine; no polling message or repeated tool result is appended to conversation.
6. A blocking invocation closes later caller-turn admission only after the current request's
   acknowledgement output ends. A finalized caller turn during the hold is not queued for
   later business processing and does not enter model conversation. Call Engine returns a
   bounded platform-owned holding response through the normal agent text/TTS path.
7. The worker sends one terminal observation to the coordinator. Success, definite failure,
   and locally timed-out `unknown` are all terminal for local admission. The observation uses
   the same invocation ID and is queued ahead of later caller work.
8. When no model request is active, the coordinator submits that observation once as a private
   engine-origin turn. It is not a second result on the old provider tool exchange and does
   not create a public caller message. Blocking admission reopens only after this continuation
   is committed or the activation terminates.

The initial holding response after submission may be generated by the LLM from the running
result. Repeated responses to caller turns during an enforced hold must not depend on the LLM;
Call Engine owns that deterministic response. Its exact configurable wording and localization
can be added without changing invocation state or model authority. Until configured wording is
implemented, use one bounded application default and preserve normal agent voice/TTS routing.

## State and ownership

Each accepted invocation has these Call Engine-owned states:

```text
requested -> accepted/running -> terminal queued -> completion admitted -> consumed
     |              |                  |
     `-> rejected   `-> terminated     `-> stale activation: discarded
```

- `rejected` means no worker was started. A bounded definite error may be returned to the
  current model request; it never creates pending state or a running acknowledgement.
- `terminal queued` retains `completed`, definite `failed`, or `unknown` outcome. A completion
  racing ahead of acknowledgement remains queued until the coordinator has registered the
  accepted invocation.
- `consumed` means the private continuation has completed, not merely that the worker stopped.
  This boundary prevents caller input from overtaking a blocking result.
- Activation transfer or shutdown terminates owned workers and destroys its hold state.
  Stale results cannot attach to a replacement activation. Speech interruption alone neither
  terminates a worker nor clears a conversational hold.

Call Engine owns workers, admission, pending/terminal maps, holding responses, completion
priority, and lifecycle. Agent Runtime owns the committed model conversation and ensures the
running acknowledgement remains present until the matching private completion is consumed.
It emits correlated submission/completion lifecycle events but does not supervise business
work. The provider adapter owns only model encoding/streaming.

## Pending model context

Committed history proves what the model was previously told, while Call Engine remains
authoritative for what is still active. Agent Runtime calls a narrow context-source boundary
before every provider generation, including repeated rounds within one request. This reporting
contract is the same for `blocking` and `non_blocking` invocations: every later LLM request
that is appropriate and admitted receives current pending state. In particular, every caller
turn admitted while non-blocking work remains pending includes each invocation's identity and
safe current status, so the model can discuss another request without forgetting the work it
must return to. Blocking suppresses only unrelated subsequent caller turns; it does not
suppress the acknowledgement round, private completion continuation, or another otherwise-
admitted request's pending context. The bounded projection contains identifiers and lifecycle
state but no arguments, results, bindings, credentials, endpoints, or raw errors:

```json
{
  "pending_tool_invocations": [
    {
      "invocation_id": "call_123",
      "tool_name": "check_balance",
      "status": "running",
      "conversation_mode": "non_blocking",
      "source_turn_id": "turn_456"
    }
  ]
}
```

The ReqLLM adapter encodes this trusted ephemeral projection on that request; it does not
append it to committed conversation or make it a public event. A terminal observation leased
but not yet consumed is distinguishable from running work. Future compaction preserves the
tool-call/running-result pair, while this projection prevents compacted or interrupted history
from becoming invocation authority.

## Multiple invocations and limits

A model response may request multiple tools. Calls are validated first and submitted in model
order under one absolute request deadline and bounded per-round/per-activation capacity. Each
accepted call receives its own running result in provider order. If any accepted call is
blocking, the activation is held until all blocking calls from all turns are consumed; a
non-blocking completion never releases another call's hold.

Partial submission is observable: already accepted workers are not rolled back if a later
submission is rejected. Their running records must still be committed so the LLM cannot lose
knowledge of real work. The rejected call receives a definite safe error. No automatic tool
retry is introduced.

Worker timeout without a definitive remote outcome reports `unknown`. Result and argument
byte limits, authorization, schema validation, provider call IDs, tool visibility, and archive
policy continue to apply. Future context compaction must preserve every unresolved tool-call /
running-result pair and invocation ID.

## Cancellation and failure boundaries

- Cancelling speech or a model stream suppresses stale output but does not cancel an accepted
  worker. Once submission succeeds, its tool-call/running-result pair is a conversation commit
  barrier and cannot be discarded with later provisional text.
- Interrupting an uncommitted private completion releases its lease without rerunning the worker.
  Replacement caller admission happens before retry for non-blocking work; blocking work emits its
  hold before retry. If that completion already committed a nested tool exchange, the original
  completion is acknowledged and the nested invocation remains pending instead of replaying either
  operation.
- A provider failure after submission leaves accepted invocations pending. The coordinator can
  start a fresh private continuation after the failed request terminates; it must not resubmit.
- Worker startup failure is definite non-submission. Worker crash is a definite failure.
  Remote timeout with no definitive result is `unknown`.
- For a blocking invocation, all terminal outcomes release the hold only after the matching
  private observation is consumed. If that continuation cannot be admitted, fail the activation
  rather than silently process caller work with missing state.
- Platform effects such as transfer or hangup are also worker outcomes. Call Engine applies
  them under room authority. A successful effect may terminate the source activation or room,
  in which case no artificial follow-up speech is required.

## Rejected alternatives

- Executing “fast” tools in the agent request worker creates two lifecycle models and makes
  latency determine correctness. A uniform submit-only boundary is selected instead.
- Repeatedly injecting `running` status wastes model context and can look like new progress.
  One committed acknowledgement is sufficient.
- Prompt-only blocking cannot enforce the requirement: a model can still answer or request
  another tool. Call Engine admission plus a deterministic holding response is selected.
- Queuing caller requests during a hold can replay stale intent after the result. Held caller
  turns receive the holding response and are not replayed.

## Migration and verification

The migration removed the old `execute`/`submit` split, Jido dispatcher, and background-only
completion protocol after submit-only tests were green. The selected definition-driven runtime
has one activation-owned invocation supervisor, registry, worker, and private-continuation path.
The optional legacy `CreateRoom` model-inference preset is now text-only: it advertises no tools
and rejects unsolicited provider tool calls without execution.

Keep responsibilities split while migrating:

- `Tool.InvocationSupervisor` owns temporary worker children and its configured maximum.
- `Tool.Invocation` owns one attempt and deadline, reporting exactly one terminal outcome.
- `Tool.InvocationRegistry` owns authoritative phases, capacity reservation, worker identity,
  completion races, delivery leases, consumed-ID tombstones, and pending projections.
- A small Call Engine submitter resolves the already-authorized binding and asks the registry
  to start it; it does not retain conversation state.
- `AgentCoordinator` owns blocking gates, deterministic holding output, completion priority,
  and serialized caller/private turns, referring to invocation IDs rather than duplicating
  worker/outcome maps.
- `Vxpipe.AgentRuntime` owns model messages, submission-result encoding, commit barriers, and
  the context-source call before each provider generation. It has no Call Engine dependency.

The retired `Tool.Dispatcher` previously owned variable projection, Jido tool-call registration,
execution, background state, and completion acknowledgement. Invocation authority now belongs to
the dedicated registry, and the selected configuration uses `maximum_tool_invocations` and
`tool_invocation_timeout_ms` because every tool shares that worker path.

The delivery boundary is lease/commit, not destructive read: a terminal observation remains
authoritative while leased to an Agent Runtime request and becomes consumed only after that
request commits. Failure or cancellation returns the lease for later delivery. This prevents
a provider failure from losing the only tool outcome.

Red/green verification must cover both conversation modes, default blocking compilation,
running acknowledgement retention across unrelated turns, deterministic hold responses,
completion priority, multiple mixed-mode calls, saturation/partial submission, timeout,
interruption, provider failure after acceptance, completion races, transfer/shutdown, stale
activation results, and no execution inside Agent Runtime or any GenServer callback.

An independent read-only review compared this target with the existing dispatcher,
invocation worker, coordinator, request transformer, tool definition/selection, and activation
supervision. It identified the former inline/background split, missing per-binding conversation
mode, duplicated coordinator/dispatcher state, destructive early completion acknowledgement,
caller-first scheduling, and absent pending-context source as migration gaps. The completed
Agent Runtime migration closes those gaps for host and Call Variables tools; remote MCP bindings
use the same model in the next milestone.
