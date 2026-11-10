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

Transfer and variable tools are derived from their respective permissions. A
prompt cannot grant access to an unselected tool or destination.

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

## Conversation behavior

`conversation_mode` defaults to `blocking`. The selected tool must finish before
that conversation resumes; caller input held during the block is discarded,
rather than replayed as a later turn. Use `non_blocking` for work that should
continue while the agent converses, subject to the provider/session's supported
semantic operations.

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
