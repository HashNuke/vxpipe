---
title: Getting started
description: Self-hostable voice agent platform.
sidebar:
  order: 1
---

## Choose your installation

<div class="installation-options">

- [Railway](usage/install/railway.md)

  Deploy Vxpipe with managed PostgreSQL on Railway.

- [Docker image](usage/install/docker.md)

  Run Vxpipe on your own server with Docker.

</div>

Both guides cover the database, public URL and environment variables. See
[Configuration](usage/configuration.md) for the complete settings reference.

## Set up your installation

Open the Console at your public URL and create the first administrator account.
Save the full HTTPS origin as the **Installation URL**.

Create a tenant and connect your AI and telephony providers through **Services**.
Provider credentials are saved per tenant. Test credentials where offered, then
save the connection; a successful test alone does not save it.

## Set up a call

1. Read [Core concepts](usage/concepts.md), then create a
   [call spec](usage/call-specs.md) with your agent's prompt, model and voice.
2. Add [tools and MCP connections](usage/agents-and-tools.md), granting only the
   tools the conversation needs.
3. Configure [telephony](usage/telephony.md), including your carrier service and
   a published incoming route.
4. Test caller audio, tool use, transfers and hangup. Review the resulting
   [call details](usage/operations.md) before accepting unattended traffic.

To contribute to Vxpipe or run a source checkout, use the
[development guide](development/local-development.md).
