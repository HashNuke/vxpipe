---
title: Agents, tools and MCPs
description: Give LLM and speech-to-speech agents the same controlled tool behavior.
sidebar:
  order: 9
---

LLM-backed and native speech-to-speech agents use the same Vxpipe tool execution
path. The model requests a selected tool; Vxpipe validates arguments and current
authority, performs the operation, and returns a bounded result. Provider adapters
translate the wire protocol. They do not own tool policy or MCP credentials.

## Tool sources

| Source | Purpose |
| --- | --- |
| Platform | Built-in actions such as current time and whole-call hangup. |
| Transfers | Move responsibility to an allowlisted participant through the shared handoff lifecycle. |
| Call variables | Read/update sections allowed by that agent's permissions. |
| MCP | Invoke a selected tool on a tenant-owned connected server. |
| Host | Application-defined tools registered by an embedding host. |

Configure an agent's tools in its call spec. A public alias is the name shown to
the model; the binding identifies the actual operation. For example, these
entries belong inside an agent's `tools` map:

```json
{
  "current_time": {"type":"platform","tool":"get_current_time"},
  "end_call": {"type":"platform","tool":"hangup"}
}
```

Agents with a dedicated TTS voice can give the caller a short announcement before
hangup or transfer. For example, an agent can invoke `end_call` with
`{"announcement":"Thanks for calling. Goodbye."}`. A transfer takes the same
optional argument alongside its destination and any required reason. Put the
sentence in the tool argument once. The call plays it in the current voice and
ignores caller interruptions until playback drains. Omitting the argument requests
immediate action. Native speech-to-speech agents use their existing tool schemas.

Every transfer to an agent starts a fresh conversation, including a return to an
earlier agent. The destination receives its own instructions and the Call Variables
sections it can read. This also applies to older publications and prepared plans.
Transfers to humans use the private briefing reason and configured transfer notice.

Transfer and variable tools are derived from their respective permissions. A
prompt cannot grant access to an unselected tool or destination.

The shared agent instructions limit caller intake to named fields in writable
Call Variables sections. Agents can answer service questions without a form.
For a configured form, the agent can see the writable schemas and current
values, ask for missing fields, and save answers through the variable tools.
Calling `read_variables` with no arguments reads the agent's permitted sections.
Passing `sections` limits the result to the requested sections.

To save one answer, call `update_variable` with the field's literal JSON value:

```json
{"section_name":"caller_requests","variable_name":"service_area","variable_value":"Florida"}
```

Use `update_variables` with `section_name` and a `data` object to merge several answers.
Each write applies to the current section, including corrections made later in the call.
On a validation error, the tool returns `error.details.expected_schema` for the
arguments the agent can submit. A rejected write leaves the stored answers intact.

When the agent determines that the caller's purpose is outside its remit and
there is no applicable handoff, the shared instructions direct it to invoke the
configured hangup tool in that turn. The same instruction applies when the
caller confirms they are finished. Configure a platform hangup binding for
agents that should end calls themselves.

At agent activation, Vxpipe loads the deployed shared instructions and combines
them with the agent prompt from the call spec. This also applies to previously
published revisions. Keep business-specific facts, tone and workflows in the
agent prompt. The dialogue format and conversation-summary instructions remain
part of the saved protocol revision.

## Select MCP tools

First [connect the server](integrations.md#connect-an-mcp) in the same tenant.
Select the required tool from its cached catalog. The published/prepared plan
pins the tool's descriptor and connection identity, without storing credentials
in the call spec or model input.

Different tenants can see different catalogs at the same endpoint. A directory
listing is a setup template, not an authorized account. New tools discovered by a
refresh do not automatically become available to published agents. A changed
catalog or connection generation can require fresh preparation.

Each agent activation owns its live MCP connections. Two calls using the same
saved connection get independent live sessions. Transferring away or ending the
call retires those sessions. Separate background refresh jobs may still contact
the server to maintain the tenant catalog; they do not reuse a call's session.

## LLM replies

LLM agents saved through ordinary editor/API authoring share one reply contract
across configured integrations.
You do not need to choose an OpenAI model or a model with native JSON Schema to
save and publish an agent. The model must still resolve normally, its options
must be valid, and a usable configured credential is required. Saving or
publishing validates configuration without making a live model request.

Vxpipe separates speech from conversation control. A speaker reply contains text;
a listener reply may contain a brief cue or remain silent. Only validated speech
text reaches audio and the transcript. Existing historical legacy publications
keep their captured behavior until explicitly replaced. Compatibility sample
installers can also create explicitly legacy publications.

A configured model can still refuse, time out, truncate its output, or return an
invalid reply. These are request failures, not successful silence. Vxpipe may
make one bounded format-correction attempt before any tool has been submitted,
within the original request deadline and remaining measured output allowance.
It does not repeat tool effects to repair a reply or silently change providers.
Generic integration support does not guarantee every upstream response will be
valid; test the selected model with your actual agent instructions and tools.

## Conversation behavior

`conversation_mode` defaults to `blocking`. The selected tool must finish before
that conversation resumes; caller input held during the block is discarded,
rather than replayed as a later turn. Use `non_blocking` for work that should
continue while the agent converses, subject to the provider/session's supported
semantic operations.

For a structured LLM voice agent, a tool call can include a short spoken message.
For example, the agent can say “Let me check” while a lookup runs. The agent gets
the actual outcome when the lookup finishes. If earlier speech is still playing,
the agent can prepare its reply and wait to speak. A caller who interrupts can
correct the request before the prepared reply plays.

Tool visibility controls what arguments/results can enter permitted history and
inspection. It is separate from whether a tool is allowed to run. The Console's
default is hidden; exposing tool data requires an explicit visibility choice.
Model results, stored history and user-facing audio are not interchangeable.

The common runtime bounds concurrency, deadlines and result size. Unsupported
native provider operations fail explicitly; shared execution does not imply that
every upstream model supports every continuation mode. Verify the actual selected
model, especially for background completion after an interruption.

## Failure and external effects

Argument validation or lost authority can reject a request before submission.
Once submitted, a timeout or lost connection may leave the remote outcome unknown.
Vxpipe does not automatically repeat a possibly mutating MCP call in that state.
Check the external system before asking the agent to retry a booking or payment.

Cancellation and call teardown stop local work and result delivery. They cannot
undo an action already accepted by an external server. A late result from a
retired activation cannot gain authority in a replacement activation. Successful
transfer or hangup can retire the source before a final spoken response.

See [Agent runtime](../development/agents-and-mcp.md) for ownership and completion
contracts, and [Operations](operations.md) for catalog and authorization failures.
