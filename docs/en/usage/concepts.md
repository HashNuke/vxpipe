---
title: Core concepts
description: How installations, tenants, call specs, participants and integrations fit together.
sidebar:
  order: 3
---

## Installation and tenants

An **installation** is one Vxpipe deployment with its accounts, public URL and
platform settings. A **tenant** owns its call specs, calls and saved connections.
One installation can serve several tenants. A user's role and tenant assignments
determine which resources they can use.

A **connection** stores the configuration and authorization for an external
service. Platform AI or telephony services can be shared where permitted; tenant
services belong to one tenant. Outbound MCP connections are tenant-owned.
The public integration directory describes available services. It contains no
tenant credentials and is separate from a connected MCP's tool catalog.

## Call specs, revisions and calls

A **call spec** is a reusable conversation definition. It selects participants,
the initial receiver, model/speech services, tools, variables and transfer rules.
Saving creates an immutable revision; publishing selects the revision for new
calls. A running call keeps its prepared revision when the spec is edited.

A **prepared call** contains a validated plan and limited admission credentials.
Joining starts the live **room**, which owns participant processes, media and
conversation state. Preparation alone is not a connected call.

A **participant** is a caller, AI agent or human destination. An agent's
**activation** is one period of responsibility in the call. Transferring away
retires that activation; returning to the same participant creates a fresh one.
Its tools and live MCP connections follow that lifetime.

## Two voice pipelines

| Pipeline | What happens |
| --- | --- |
| LLM with speech models | Speech-to-text transcribes the caller; an LLM produces text/tool requests; text-to-speech speaks the response. |
| Native speech-to-speech | A provider handles audio input and output directly. Vxpipe still owns call policy, transfers and tool execution. |

Both use the same platform tools and connected MCP tool behavior. Providers
differ in available models, voices and wire protocols. Use the supported choices
shown by the integration, rather than assuming every upstream option is exposed.

## State and visibility

**Call variables** hold structured state shared according to the call spec's
visibility rules. **History** records permitted events and transcripts.
**Model context** is the selected conversation state supplied to an agent; it can
be compacted without rewriting stored history or expanding access to private data.

Private transfer briefings, caller audio, recordings and tool results each follow
their own visibility rules. Being present in a room does not grant access to all
of its media or state.

## The two directions of MCP

- **Platform MCP:** an external AI client connects to Vxpipe's `/mcp` endpoint and
  authorizes through Console login and consent to manage permitted resources.
- **Connected MCP:** an agent inside a call uses a tenant's external MCP server.
  Each activation owns its live connections. The tenant's authorized tool catalog
  is cached separately in PostgreSQL.

See [Agents, tools and MCPs](agents-and-tools.md) for calls and
[HTTP API and platform MCP](api-and-mcp.md) for external clients.
