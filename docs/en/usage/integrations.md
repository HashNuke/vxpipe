---
title: Integrations and credentials
description: Connect AI, speech, telephony and tenant MCP services.
sidebar:
  order: 6
---

Open a tenant's **Integrations** to see its connected services, browse categories
or search the public directory. Platform integrations can supply shared native
AI and telephony services; MCP connections always belong to a tenant.

## Native AI, speech and telephony

Choose a provider, enter its credential fields, optionally **Test**, then **Save**.
Testing performs a bounded provider check where supported and does not save.
Saving validates the credential shape and encrypts it; it does not prove upstream
authorization. A provider without a safe test can still be saved.

Listings return masked metadata. Replacing credentials updates the existing
connection identity; it does not reveal the old secret. A tenant override takes
precedence over a platform binding by presence. An invalid tenant override fails
instead of silently using the platform account.

Select models and voices in the call spec. A provider's presence in the public
directory is not sufficient for execution: the installed Vxpipe adapter and its
capability catalog determine supported options.

For trusted source-host provisioning, the CLI accepts secrets through protected
stdin, for example:

```shell
mix vxpipe.provider_credential.provision \
  --tenant TENANT_KEY --provider google < protected-google-credential.json
mix vxpipe.provider_credential.list --tenant TENANT_KEY
```

The Google input is `{"api_key":"REPLACE_WITH_PROVIDER_KEY"}`. Keep the actual
file outside source control, restrict its permissions and remove it when no
longer needed. CLI default bindings and Console-created binding names can differ;
select the intended saved credential rather than assuming an arbitrary name.

## Connect an MCP

Choose a listed MCP or **Connect other MCP**. A custom connection needs the full
MCP endpoint, including its path. Do not put tokens in the URL. Endpoint preflight
checks available authentication metadata; it does not invoke a business tool.

Supported connection methods include anonymous access, bearer token, Basic,
validated custom headers and supported OAuth flows. Anonymous mode is an explicit
choice, never a fallback after authentication failure.

For OAuth, complete the provider's browser authorization. CIMD identifies the
installation through its client metadata URL; DCR registers a client; neither
replaces the user's consent. A provider may instead require a manually registered
client. Use the form's advertised setup method and save a public HTTPS
Installation URL before these flows.

After credentials are saved or OAuth succeeds, Vxpipe initializes the MCP and
discovers its tools. A token alone is not readiness. A connected server may
legitimately expose no tools. Test the actual operation you need: discovering a
booking tool does not prove the authorized account can make a booking.

## Catalogs and refresh

Each saved connection has its own PostgreSQL catalog cache. Two tenants connected
to the same server may see different tools because their upstream accounts have
different permissions. Catalogs are not shared by endpoint or directory entry.

Use **Refresh tools** for an immediate refresh. Background jobs also refresh stale
catalogs: the default expiry is one hour, with a sweep every minute. Scheduling
within the last 30 minutes suppresses another job; after that window a stale
catalog is eligible again unless matching work is still queued/running/retryable.
These intervals are [application settings](configuration.md#application-settings).

A failed refresh keeps the last complete catalog and its old freshness time.
New tools are not automatically added to an agent. Select them explicitly and
prepare a fresh call after relevant catalog changes.

## Reconnect and disconnect

Listed duplicates reopen the existing connection. Disconnect revokes the saved
authorization and removes its usable secrets/catalog while retaining its identity.
An explicit reconnect with fresh authorization restores that identity, so a
published spec can use it again with a newly prepared call.

Old prepared generations remain invalid. An already submitted external tool may
still finish; disconnect cannot undo an action accepted by the remote service.
Later submissions must resolve current authorization and fail after revocation.

Directory outages do not erase saved connections. Connected inventory and built-in
native services remain available, and tenant operators can still configure a custom
MCP. An unavailable connection-status read is shown as unknown, not as permission
to create a duplicate.

See [Agents, tools and MCPs](agents-and-tools.md) to select tools for a participant.
