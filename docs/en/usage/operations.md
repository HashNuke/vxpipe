---
title: Operations and troubleshooting
description: Inspect calls, diagnose common failures and maintain credentials and catalogs.
sidebar:
  order: 11
---

## Establish what is working

`GET /healthz` returns `200 ok` when the HTTP handler is running. It does not query
PostgreSQL, validate provider credentials or establish media readiness. Check
login, a saved-resource read and an actual call separately after configuration
or deployment changes.

The tenant Calls directory shows **ongoing** or **ended**. Prepared calls count
as ongoing, so that label alone does not mean a caller joined. Open the call for
its pinned revision, timeline, transcripts, tool outcomes, variables and usage.

Inspection reads archived facts from PostgreSQL. An ongoing call may have newer
events than its persisted snapshot. `complete`, `incomplete` and `unconfirmed`
describe evidence, not a guess. Missing usage is not zero cost; a captured empty
tool result differs from a result that was not captured.

Recordings and immutable call-detail publications are separate artifacts. They
require configured object storage and relevant capture permissions. A readable
inspection page does not imply a recording exists.

## Common failures

| Symptom | Check |
| --- | --- |
| Startup rejects configuration | Variable names in the error, selected database alias, keyring JSON and key length, `APP_HOST`, signing secret length. Do not log secret values. |
| Credential save fails | Encryption keyring availability, tenant/write permission, required provider fields and database connectivity. |
| Credential test succeeds but call fails | Save the credential, select the intended binding/model, and check provider quota/capabilities. A credential probe is not call acceptance. |
| Call will not prepare | Published revision, route, selected credentials, MCP catalog/configuration generations and variable validation. |
| Browser joins but is silent | Microphone permission, chosen devices, ICE/media reachability, actual media connection, STT/TTS/model errors and output policy. HTTPS signaling alone is insufficient. |
| Phone call never arrives | Carrier number/application association, exact scoped webhook URL, verification credentials, published number route and public HTTPS. |
| Phone call connects without audio | WSS upgrade support, carrier media stream, codec negotiation and permission/readiness failures. |
| Transfer stalls | Allowed destination, destination readiness/acceptance, originating service, timeout and wait/cue completion. Inspect failure recovery before retrying. |
| Tool unavailable | Explicit selection, schema pin, participant authority, current connection status and supported model/session operations. |
| Tool times out after submission | Treat the external result as potentially unknown. Check the external system before repeating a mutation. |
| Catalog stale or reconnect required | Background job state, endpoint availability, current grant and authorization scopes. Refresh is not a substitute for new consent. |
| Object download fails | Exact call/artifact ownership, bucket configuration, object availability and storage credentials. |

Use call IDs and bounded error codes when correlating logs. Avoid copying caller
data, raw transcripts, tokens, headers or credential envelopes into diagnostics.

## MCP catalog maintenance

Oban uses the application's PostgreSQL database. Its maintenance sweep selects
stale connected records; catalog workers open temporary sessions, discover all
pages and conditionally save a complete snapshot.

- `refreshed_at` advances only after a successful complete catalog publication,
  including a valid empty or unchanged catalog.
- `refresh_scheduled_at` advances only when a new job is committed.
- A recent scheduling timestamp suppresses duplicates for 30 minutes by default.
  A matching unfinished job also suppresses another enqueue after that window.
- Failed refreshes retain the last complete catalog and old freshness time.
  Replacement/disconnect prevents obsolete jobs from publishing results.

Inspect Oban's job/attempt state when work remains stale. Repeated authorization
failure needs reconnect; queue retries cannot grant missing access. Queue
concurrency is per node. Configure expiry/cadence in application settings, not
new environment variables.

## Rotate the installation encryption key

This changes encryption at rest, not the third-party API key:

1. Add the new key to every reader while retaining the old active write key.
2. Switch every writer to the new key ID, retaining both decrypt keys. Restart
   instances whose repository context captured the old keyring.
3. Drain operations that captured old key material, including in-flight OAuth
   renewal. Then run bounded batches from the trusted source host:

```shell
mix vxpipe.provider_credential.reencrypt --batch-size 100
mix vxpipe.mcp_credential.reencrypt --batch-size 100
mix vxpipe.mcp_oauth.prune --batch-size 100
```

4. Repeat until provider and MCP stores have no old-key rows. Inspect the prune
   command's `pending_by_key`; retain old keys until pending OAuth attempts are
   claimed or expired and removed. A zero count from one store is insufficient.
5. Remove the old key only after all writers/operations have switched, then
   restart and verify credential reads with the new key alone.

Re-encryption includes revoked rows and preserves identity/version/status. A
failed batch commits no partial replacement. Never change bytes under an existing
key ID. Packaged equivalents of these Mix commands remain delivery work.

## Backup, restart and retention

Back up PostgreSQL, object storage and the keyring through their respective host
mechanisms. Keep the keyring recoverable separately from database backups. A
restore drill must verify decryption and artifact access as well as table recovery.
There is no packaged automated backup/restore procedure yet.

Live room state and provider sessions are not durable. Drain calls before planned
replacement; a database backup cannot restore an interrupted audio conversation.
Durable cancellation/terminal evidence prevents cleanup from pretending that an
unknown outcome completed successfully.

Whole-call retention/deletion is still an unfinished milestone. Oban job-history
pruning is not call-data retention. Do not assume old calls, recordings or OAuth
attempts are all removed by the catalog maintenance sweep.
