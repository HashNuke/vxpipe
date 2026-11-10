---
title: Configuration
description: Deployment variables, application settings and tenant configuration.
sidebar:
  order: 4
---

Vxpipe has three configuration layers:

| Layer | Use it for |
| --- | --- |
| Deployment environment | Database connection, public hostname, signing/encryption secrets and object storage. |
| Elixir application configuration | Runtime limits, queues, refresh intervals and enabled host integrations. |
| Console and call specs | Accounts, Installation URL, saved provider credentials, models, voices, tools and tenant call behavior. |

Provider API keys belong in saved connections. They are not global deployment
variables. The environment is read centrally in
[`config/runtime.exs`](../../../config/runtime.exs); defaults and internal limits
live in [`config/config.exs`](../../../config/config.exs).

## Deployment settings

| Variable | Meaning |
| --- | --- |
| `VXPIPE_DB_URL` or `DATABASE_URL` | PostgreSQL URL. Required for hosted tenant operation. `VXPIPE_DB_URL` wins. |
| `VXPIPE_DB_POOL_SIZE` or `DB_POOL_SIZE` | Positive pool size; default `10`. The prefixed value wins, including over `pool_size` in the URL. |
| `APP_HOST` | Public hostname, without scheme/path. Required in production. Non-loopback hosts advertise HTTPS; TLS is terminated by the hosting proxy. |
| `PORT` | Internal HTTP port; default `4000`. Public production hosts bind on all IPv4 interfaces. |
| `SECRET_KEY_BASE` | Stable random signing secret, at least 64 bytes. Required in production and for a non-loopback development listener. |
| `VXPIPE_CREDENTIAL_KEY_ID` | ID of the active credential encryption key. |
| `VXPIPE_CREDENTIAL_KEYS` | JSON object mapping immutable key IDs to base64-encoded 32-byte random keys. Include older keys while stored data still needs them. |
| `TELEPHONY_HOST` | Optional explicit HTTPS callback/media origin, including a mount prefix when needed. Overrides the Installation URL for telephony. |
| `VXPIPE_MCP_RESOURCE_URL` | Optional explicit resource audience for inbound platform MCP; defaults to the public origin plus `/mcp`. |
| `VXPIPE_INTEGRATIONS_DIRECTORY_ORIGIN` | Optional HTTPS origin for the public integration directory. Normally use the bundled default. |
| `STORAGE_BUCKET` | Optional shared S3 bucket for recordings and call-detail publications. Requires persistence. |
| `AWS_REGION`, `AWS_ENDPOINT` | Region (default `us-east-1`) and optional S3-compatible endpoint. |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | Optional object-storage credentials. Otherwise ExAws uses its credential chain. Session token is needed only for temporary credentials. |

Both encryption variables must be supplied together. Omitting both permits
credential-free operation, but saved secrets cannot be provisioned or resolved.
Never replace key bytes under an existing ID. Back up the keyring separately
from PostgreSQL; losing it makes encrypted credentials unrecoverable.

Empty database settings are treated as absent. Invalid selected values fail
startup instead of silently using a lower-priority alias. Development/test
checkout defaults come from `bin/setup`; production must supply its own settings.

## Installation URL

During first account setup, save the canonical public origin, such as
`https://voice.example.com`. Superadmins can edit it under **Settings →
Installation** (`/platform/installation`). Public HTTP is rejected; loopback HTTP
is allowed for local development.

This saved origin supplies carrier callback/media addresses and MCP OAuth
metadata. It does not configure DNS, TLS, listeners or provider dashboards.
Deployment overrides above retain precedence. Request headers never establish
the installation's identity.

Other application instances normally observe a change within 30 seconds plus
the bounded read time. Existing carrier legs retain their initialized URL;
new legs use the current setting. Keep an old origin reachable until those calls
end, update carrier-dashboard webhooks, and reconnect affected OAuth clients.

## Application settings

These are application configuration, not environment variables:

| Setting | Current default |
| --- | --- |
| `:vxpipe_calls, :mcp_catalog_refresh` | Catalog expiry `3_600` seconds; scheduling suppression `1_800` seconds; batch size `100`. |
| Persistence Oban queues | `maintenance: 1`, `mcp_catalog: 4`; catalog sweep every minute. |
| `:vxpipe_calls, :mcp_catalog_discovery_timeout_ms` | `10_000` ms. |
| `:vxpipe_persistence, :mcp_catalog_worker_timeout_ms` | `30_000` ms. |
| Calls `:call_duration` | Maximum call duration `1_800_000` ms, with tenant overrides. |
| Engine `:call_lifecycle` | Readiness timeout `30_000` ms; idle timeout `15_000` ms. |
| Engine `:agent_runtime` | Tool timeout `30_000` ms; at most four simultaneous tool invocations. |

Change these through the owning application's configuration and restart the host
as required. See [Agent runtime](../development/agents-and-mcp.md) for scheduling
and lifecycle semantics. Call specs select supported provider/model/voice options;
they cannot set transport URLs, authentication headers or arbitrary modules.

## Development-only settings

`VXPIPE_DEV_TENANT` selects a provisioned tenant for the managed voice playground.
`VXPIPE_DEV_TLS`, `VXPIPE_DEV_TLS_CERTFILE` and `VXPIPE_DEV_TLS_KEYFILE` control local
TLS. `VXPIPE_RECORDING_ENABLED=true` enables the development recording path when
object storage is configured. `MORSE_CODE_API_BASE_URL` is used only when the
remote Morse test provider is selected.

`bin/dev` loads the checkout's ignored `.env`; direct Mix commands do not. See
[Development workflow](../development/local-development.md).
