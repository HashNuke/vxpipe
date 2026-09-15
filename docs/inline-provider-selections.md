# Inline provider selections

Status: inline tenant selections and all existing provider readers are implemented and independently
reviewed. Final configuration acceptance is tracked in the [milestone ledger](milestones/tenant-provider-credentials-and-platform-configuration.md#evidence-ledger).

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

Agent Runtime translates Google and Zenmux model selections to ReqLLM internally. Public configuration cannot
select ReqLLM, a module, request callback, headers, endpoint or credential. The initial option
allowlist covers bounded generation settings and mutually exclusive Google thinking controls.
It deliberately excludes provider-managed tools and transport/authentication fields.

Google requests pin `https://generativelanguage.googleapis.com/v1beta` and use header
authentication. An explicit API key alone was insufficient: installed ReqLLM can consult an
application-configured provider endpoint. The synthetic test seeds a conflicting endpoint and
observes the actual generated request before redirecting it to a local test server.

Zenmux preserves the existing `openai/gpt-5` model path and native routing contract through
one named tenant Zenmux credential. Its endpoint is fixed to `https://zenmux.ai/api/v1`; public
options cannot replace it or supply authentication. For example, a model selection can be:

```json
{
  "provider": "zenmux",
  "model": "openai/gpt-5",
  "credential_name": "router",
  "options": {"temperature": 0.2, "max_tokens": 256},
  "provider_options": {
    "provider": {
      "fallback": "anthropic",
      "routing": {
        "type": "priority",
        "primary_factor": "quality",
        "providers": ["openai", "anthropic"]
      }
    }
  }
}
```

The supported native object has optional `fallback` (boolean or provider name) and `routing`
fields. Routing accepts `type` (`priority`, `round_robin`, `least_latency`), `primary_factor`
(`cost`, `speed`, `quality`) and one to sixteen provider names. Names contain at most 64 ASCII
letters/digits, dots, underscores or hyphens and start with a letter/digit. Unknown fields,
credential/transport options and executable values fail local validation. Only these fixed
JSON keys are translated to ReqLLM's internal atom keys; the encoded routing object is unchanged.
The request builder translates `max_tokens` to Zenmux's `max_completion_tokens` field.
The [provider inventory](existing-provider-credentials.md) records the pre-cutover support evidence;
this migration adds no direct OpenAI/Anthropic authentication or other SDK provider integration.

The Google text adapter selects streaming explicitly. The installed model data omitted the
`streaming.text` field even for the sample model, causing the old automatic check to choose
non-streaming. Google documents `streamGenerateContent` for text generation in its
[API reference](https://ai.google.dev/api/generate-content#method:-models.streamgeneratecontent).
This choice belongs to the adapter; it does not add a public transport switch.

Selection identity hashes tenant, provider, model, options and credential binding name for usage
and TTS caching. Runtime rejects old schema plans and malformed selections instead of restoring
profile support. Replace old definitions and prepare fresh calls through the existing administration
workflow below; no profile-conversion or call-draining subsystem is required.

## Replace old definitions and prepared calls

1. Provision each required tenant provider binding through [credential setup](provider-credential-storage.md).
   Register any phone services through [tenant telephony setup](tenant-telephony-services.md).
2. Author a current `20260915.01` definition with inline selections, replacing old profile references.
   Save it as a new immutable revision and publish it through the existing
   [definition administration](tenant-control-plane.md). Missing credentials reject the write.
3. Prepare new calls from the published routes. Hosted preparation pins safe carrier service
   identity, and activation resolves current tenant credentials.
4. Preserve old revisions and call history. Old-schema or unbound hosted phone plans cannot start;
   do not rewrite their serialized history or infer new bindings for them. Existing initialized
   clients keep their normal owned lifetime; starting a new client requires fresh resolution.

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

The [Zenmux checkpoint](../labnotes/20260916-0033-zenmux-tenant-credentials.md) records focused
red/green checks for encrypted provisioning, named tenant resolution, persisted selections,
unavailable bindings and exact request construction with conflicting ambient credentials/endpoint.
The request retains its tool schema and provider-reported model/usage. No live Zenmux call is claimed.

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

Fixture/example migration is complete. The original checkpoint-1 run passed **1,489 tests,
zero failures, 30 exclusions** (seed 235296), with all five root gates passing. Its initial reviewer
follow-up hit a usage limit; that is historical evidence, not the current review status. Subsequent
independent reviews cover the implemented reader checkpoints and final configuration changes.
The final reviewed source at `58d7b34` passes **1,622 tests, zero failures, 39 exclusions** and all five
root gates; all seven credential/configuration checkpoints are complete. Earlier intermittent native
audio observations remain recorded; a passing run does not establish their cause.
See the [current milestone ledger](milestones/tenant-provider-credentials-and-platform-configuration.md#evidence-ledger)
and [original checkpoint labnotes](../labnotes/20260915-1719-inline-tenant-voice.md).
