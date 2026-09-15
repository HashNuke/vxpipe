# Inline provider selections

Status: checkpoint 1 is implemented and verified. The synthetic tenant voice flow and all five
umbrella completion gates pass. Final independent implementation review remains open.
This document records the implementation decision, not deployment readiness.

## Ownership and representation

Schema `20260915.01` carries each capability's actual provider, provider-local model,
`options`, `provider_options`, and optional `credential_name` (default `default`).
An override replaces the entire selection. Opening TTS has its own selection.
The typed selection has no profile field, private payload, repository context or encryption key.

Call Engine owns parsing, a closed capability-to-adapter catalog, and the neutral credential
source contract. Calls implements that contract through its provider repository; Persistence
decrypts the exact tenant/provider/name binding. Engine does not depend on Calls or Persistence.
Local Morse and explicitly configured test fixtures need no tenant credential.
The fixture configuration cannot select the hosted ReqLLM adapter; hosted model calls must
use their upstream provider selection and the tenant credential source.

Calls checks credentials separately from ordinary draft support validation. Missing, revoked,
unreadable or mismatched credentials prevent save; publication and preparation check again.
Capability startup resolves a fresh private snapshot inside the existing preparation worker.
The snapshot can live for its activation, but must not enter a definition or serialized plan.
Save, publication and web preparation also use the credential repository's `with_active`
transaction boundary for the final database write. It acquires shared row locks in provider/name
order and checks/decrypts the current binding while those locks are held. Revocation/rotation cannot
overtake that write. Missing, revoked or unreadable records roll back the operation; no private
snapshot is given to its callback. The callback performs only database work through repositories
sharing the same Repo/transaction. The hosted runtime already composes these adapters over one Repo.
Parsing, model option validation and opening-audio preparation happen before this transaction.

Every new caller STT process resolves current credentials, including entry participants previously
prepared by the room. Its bounded preparation task links to the connection so caller exit also
cancels lookup. An already running STT process keeps its original snapshot. The room's readiness
metadata no longer selects credentials for later process creation.

## Provider translation

Agent Runtime translates Google model selection to ReqLLM internally. Public configuration cannot
select ReqLLM, a module, request callback, headers, endpoint or credential. The initial option
allowlist covers bounded generation settings and mutually exclusive Google thinking controls.
It deliberately excludes provider-managed tools and transport/authentication fields.

Google requests pin `https://generativelanguage.googleapis.com/v1beta` and use header
authentication. An explicit API key alone was insufficient: installed ReqLLM can consult an
application-configured provider endpoint. The synthetic test seeds a conflicting endpoint and
observes the actual generated request before redirecting it to a local test server.

The Google text adapter selects streaming explicitly. The installed model data omitted the
`streaming.text` field even for the sample model, causing the old automatic check to choose
non-streaming. Google documents `streamGenerateContent` for text generation in its
[API reference](https://ai.google.dev/api/generate-content#method:-models.streamgeneratecontent).
This choice belongs to the adapter; it does not add a public transport switch.

Selection identity hashes tenant, provider, model, options and credential binding name for usage
and TTS caching. Runtime rejects old schema plans and malformed selections instead of restoring
profile support. Stored revision conversion and prepared-call draining remain explicit final-cutover
operations from the milestone.

## Rejected alternatives

- A profile lookup or legacy environment fallback would preserve the configuration path being
  removed and could select another tenant's credentials.
- Storing a resolved provider configuration in the prepared plan would persist plaintext secrets
  and make revocation ineffective for later activation.
- Doing database lookup in a room callback would block room authority on storage.
- Treating credential errors as draft validation metadata would allow unauthorized revisions
  and routes to be inserted.
- Replacing Google with a credential-free fixture in acceptance would not exercise tenant
  credentials through the real model adapter.

## Speech transport privacy

The installed WebSockex 0.5.1 client emitted its connection, including authorization headers,
in every connection/frame telemetry event. A local WebSocket regression test reproduced the
disclosure for STT and TTS. Engine now owns a small supervised transport using the existing
Mint/Mint.WebSocket dependencies, with logging disabled and generic connection errors.
The request headers are used for the upgrade only; routine state inspection and crash status
exclude buffered provider data. ReqLLM still requires WebSockex transitively, so its lock entry stays.

[Mint.WebSocket](https://github.com/elixir-mint/mint_web_socket) supplies framing and upgrade
validation; Vxpipe supplies lifecycle, ping replies and TTS output acknowledgement. The transport
does not reconnect automatically. TTS acknowledgement is asynchronous so close remains responsive;
an unacknowledged frame closes at the existing 15-second deadline. Active-once socket delivery
pauses further reads while audio output is pending. The handshake also preserves a first provider
frame that arrives in the same read as the HTTP upgrade.

Filtering telemetry in one subscriber was rejected because other subscribers would still receive
the raw headers. Editing the installed dependency was rejected because it would not be reproducible.
The local protocol checks run in the explicitly excluded integration lane; no live provider keys
or external speech services are used by these checks.

## Verification and remaining work

Focused red/green evidence currently covers inline parsing, whole-selection overrides, safe
option rejection, provider translation, tenant isolation, fresh publication/preparation checks,
private source resolution, constructor authentication, serialized-selection rejection and STT
state inspection. A PostgreSQL-backed test exercises provisioning through a synthetic
Google/Deepgram voice reply with the actual Google request builder.

An early synthetic attempt used non-streaming because of the omitted model metadata and bypassed
the streaming interceptor. It used only a synthetic key and failed. The test now verifies the
explicit streaming selection before activation; the successful run used the local request server.

Runtime no longer reads global Google/Deepgram keys or development speech/model switches.
The Console uses `VXPIPE_DEV_TENANT` to reuse an explicitly provisioned tenant and keeps its
call key server-side. An isolated browser check prepared calls before and after restart with
one tenant, and inspected desktop/mobile rendering. It did not use live provider credentials.

Fixture/example migration is complete. The umbrella passes **1,489 tests, zero failures,
30 exclusions**, seed 235296, with module preloading, serialized test-file compilation and
concurrency four. Formatting, warnings-as-errors compilation, strict Credo and the unused-lock
check pass. Earlier intermittent native audio/cleanup observations are recorded in the labnotes;
this green run does not establish their cause. Final independent implementation review remains
open. The requested reviewer supplied an initial source review; its follow-up was
blocked by a usage limit, so no final independent approval is claimed. See the [milestone](milestones/tenant-provider-credentials-and-platform-configuration.md)
and [checkpoint labnotes](../labnotes/20260915-1719-inline-tenant-voice.md).
