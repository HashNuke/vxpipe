---
title: Vxpipe documentation
description: Build, operate and extend voice calls with AI agents, tools and human transfers.
sidebar:
  order: 0
---

Vxpipe runs voice conversations between callers, AI agents and people. A call spec
defines the participants, models, speech services, tools and permitted transfers.
The Console manages tenants, connections, call specs and call inspection.

## Use Vxpipe

Start with [Getting started](usage/getting-started.md). The runnable setup today
uses a source checkout. [Docker](usage/install/docker.md) and
[Railway](usage/install/railway.md) describe the intended packaged installation;
the image and its release procedure are still pending.

- [Core concepts](usage/concepts.md)
- [Configuration](usage/configuration.md)
- [Accounts, tenants and access](usage/administration.md)
- [Integrations and credentials](usage/integrations.md)
- [Call specs and variables](usage/call-specs.md)
- [Telephony and transfers](usage/telephony.md)
- [Agents, tools and MCPs](usage/agents-and-tools.md)
- [HTTP API and platform MCP](usage/api-and-mcp.md)
- [Operations and troubleshooting](usage/operations.md)

## Develop Vxpipe

- [Development workflow](development/local-development.md)
- [Architecture](development/architecture.md)
- [Call runtime and lifecycle](development/call-runtime.md)
- [Speech and media runtime](development/speech-runtime.md)
- [Agent runtime, tools and outbound MCP](development/agents-and-mcp.md)
- [Identity, persistence and security boundaries](development/security-and-persistence.md)
- [Adding providers and integrations](development/providers-and-integrations.md)
- [Console and client development](development/console-and-clients.md)
- [Testing and verification](development/testing.md)

This handbook describes the checked-in implementation. Installation plans are
marked explicitly. Implementation progress and dated acceptance evidence live in
the repository's [milestones](../../labnotes/milestones/index.md), outside the
published handbook.
