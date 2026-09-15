# Tenant-scoped provider credentials and platform configuration

Status: credential/configuration cutover authorized; scope corrected on 2026-09-15.
Preparatory cleanup and checkpoints 1, 2 and 5 are complete. Of seven checkpoints, three are complete,
two are partial and two are not started. The latest full umbrella run retains one native Morse
failure; the milestone and common acceptance gates remain unchecked.
The user approved removing capability profiles, keeping ReqLLM internal, and including
Telnyx/Twilio credentials. The initial specification and follow-up scope audit were independently
reviewed. Final independent implementation review and the remaining checkpoints are open.

Prerequisites: the implemented workflows in
[Tenant definitions and API-key administration](tenant-definitions-and-api-keys.md),
[Prepared calls](prepared-call-admission.md), [ReqLLM agent runtime](reqllm-agent-runtime.md),
[Local Morse providers](morse-code-audio-providers.md), [Opening audio](opening-audio-and-call-lifecycle.md),
[Agent transfers](agent-transfers.md), [Human transfers](human-web-transfers.md),
[Telnyx calls](telnyx-calls.md), [Twilio calls](twilio-calls.md), and
[Recordings](streaming-recordings.md).
The original Twilio live-provider acceptance remains open; writing this plan or running synthetic
carrier checks does not complete it. Packaging/retention retain the index's review hold.

Design sources: [Tenant control plane](../tenant-control-plane.md),
[Architecture](../architecture.md), [ReqLLM runtime](../reqllm-agent-runtime.md),
[Opening audio contract](../opening-audio-contract.md), and
[Context compaction](../context-compaction.md).

## Scope correction — 2026-09-15

The user clarified: existing call paths should read tenant credentials from the database.
This milestone changes credential/configuration ownership and verifies the affected readers.
It does not add transfer, recovery or carrier workflows, or require replaying every acceptance
scenario from their completed milestones. A failing credential lookup follows existing failure
handling. Focused integration checks prove that the correct tenant binding reaches each adapter.

The previous plan over-scoped this change. Remove third-party API-key rotation/revocation
operations, carrier key-overlap machinery and broad call-flow demonstrations. The user separately
confirmed platform encryption-key rotation: the platform operator owns that key, and re-encrypting
stored values does not change tenants' upstream credentials. At this scope correction, one of
seven checkpoints was complete, two were partial and four were not started. Current progress is
recorded in the evidence ledger; the scope correction itself counted as no implementation progress.
See [the scope decision](../credential-cutover-scope.md).

The follow-up scope audit below limits provider migration to integrations supported before this
cutover. Reuse existing keyring, leg/reservation and acceptance-test foundations. SDK catalogs,
website logos and historical review findings do not create new feature requirements.

## Outcome and configuration ownership

A tenant provisions an encrypted provider credential, then saves and runs a definition that
selects the actual provider and model. Saving fails before a revision is written if a required
tenant credential is unavailable. Telnyx and Twilio use the same tenant credential boundary for
carrier commands and ingress authentication. Platform infrastructure uses deployment environment
variables. There is no runtime TOML file or capability-profile lookup.

| Configuration | Owner and source |
| --- | --- |
| Speech/model provider, model, common options, provider-specific options | Inline call-definition data, persisted as immutable revisions |
| AI/speech credentials, including Google and Deepgram | Encrypted tenant records in PostgreSQL |
| Telnyx API key; Twilio account SID and auth token | Tenant provider records; secret payloads encrypted |
| Carrier account/connection identity, verification configuration, ingress key, originating number | Tenant telephony service binding in PostgreSQL, linked to its tenant credential |
| Database URL/pool, S3 credentials/bucket/region/endpoint, deployment HTTP/TLS and callback origin | Platform environment settings read in `config/runtime.exs` |
| Credential encryption keyring | Platform secret supplied outside PostgreSQL |
| ReqLLM, provider modules, transport modules | Internal implementation selected by closed code-owned catalogs |

Existing provider integrations use tenant credentials. Missing tenant credentials must never
fall through to platform storage settings or SDK credential discovery. Adding providers or
authentication modes that Vxpipe does not already support is outside this milestone.
Telnyx's webhook public key is verification metadata, not a private signing key; associate it with
the tenant service and version it with the authentication configuration.

This decision supersedes the discarded runtime TOML proposal and the older proposed
deployment-config-file contract. Definition JSON remains the portable behavior
document. Removal applies to provider env/global-application fallbacks as well as TOML.

Removal means deleting the old provider configuration readers, merges and fallback branches,
not retaining them behind precedence rules, deprecation warnings, feature flags or compatibility
modes. This covers provider credentials and provider/model/option settings from environment
variables, TOML, global application configuration and capability profiles, including
`provider_api_key_environment`. Internal adapters receive explicit tenant DB credentials and
definition-owned options; their libraries' ambient credential discovery must never be reached by
Vxpipe calls. Platform infrastructure env settings remain supported, but cannot supply tenant
provider credentials. Missing tenant credentials fail closed even if old settings are present.
Explicit migration tooling and read-only historical inspection are not live configuration sources
and must never run automatically as a save/startup/activation fallback.

### Platform database environment contract

Resolve these independent platform settings in `config/runtime.exs`, in the stated order:

| Setting | First choice | Second choice | When neither is set |
| --- | --- | --- | --- |
| Database URL | `VXPIPE_DB_URL` | `DATABASE_URL` | Development: `postgres://localhost/vxpipe_dev` |
| Database pool size | `VXPIPE_DB_POOL_SIZE` | `DB_POOL_SIZE` | Default pool size: `10` |

Development requires neither database variable pair to be set. Local PostgreSQL and the
`vxpipe_dev` database still need to be available; this does not introduce a default encryption
key or bypass tenant credential provisioning. Explicit environment overrides remain available.
Outside development, never silently select `vxpipe_dev`; hosted DB-backed operation requires
one of the two URL variables. Embedded credential-free operation retains its existing boundary.

Treat unset, empty and whitespace-only values as absent. Select the first non-empty value in
each pair, then validate it: an invalid higher-priority value is an error, not permission to use
the lower-priority value. Pool size must be a positive integer. Diagnostics must identify the
setting without printing the database URL or credentials. These are intentional platform aliases,
not provider-configuration fallbacks. Retire `VXPIPE_DATABASE_URL`; do not keep it as a third alias.

Preserve the dedicated test database and Sandbox pool configuration. Normal database URL/pool
variables must not override `config/test.exs` or accidentally direct tests to development or
production databases; retain the existing explicitly test-scoped overrides.

### Shared platform artifact bucket

Recordings and call-details publications use one platform bucket, selected by `STORAGE_BUCKET`.
Use `AWS_REGION` and optional `AWS_ENDPOINT` for the destination, `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` for static credentials, and optional `AWS_SESSION_TOKEN` when supplying
AWS temporary credentials. The user chose these unprefixed names in place of the earlier
`VXPIPE_BUCKET` proposal. Their object keys retain the existing distinct recording/publication
namespaces. Remove the separate `VXPIPE_RECORDING_S3_*` and `VXPIPE_CALL_DETAILS_S3_*` settings
and fallback rules. A deployment cannot configure independent destinations for these two artifacts.
Preserve enablement: a configured database and non-empty bucket enable call-details publication;
recording still requires its explicit enable flag and must fail safely if its bucket is missing.
Treat unset/blank `STORAGE_BUCKET` as absent. Validate an active destination and reject malformed
endpoint configuration without printing secrets. Retired-only settings supply no destination;
they must neither enable publication nor rescue explicitly enabled recording without a new bucket.
The user requested this configuration change on 2026-09-15; it can ship as a separate coherent
commit before the remaining provider-reader work, while checkpoint 7's platform cutover remains open.

## Code review baseline and change map

These planning observations were captured before the preparatory cleanup, including the
since-discarded uncommitted TOML work. They identify the vertical slices’ integration boundaries.

| Reviewed code | Current behavior and required change |
| --- | --- |
| [Capabilities](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_definition/capabilities.ex), [OpeningAudio](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_definition/opening_audio.ex) | Parse profile strings. Replace them with inline selections in defaults, participant overrides and independent opening TTS. |
| [DefinitionCompiler](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/definition_compiler.ex), [CapabilitySelection](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_definition/capability_selection.ex) | Resolve a required `capability_profiles` registry and retain `profile`. Remove that lookup/field and separate public provider identity from adapter identity. |
| [Definitions](../../apps/vxpipe_calls/lib/vxpipe/calls/definitions.ex) | Saves unsupported catalog references as draft validation errors; publishing checks the stored errors only. Add hard credential gates before save and fresh checks at publication/preparation. |
| [PrivateMaterial](../../apps/vxpipe_calls/lib/vxpipe/calls/private_material.ex) | Rejects keys such as `credential`, `api_key`, and `token`. Add a typed non-secret reference without weakening payload rejection. |
| [CredentialRepository](../../apps/vxpipe_calls/lib/vxpipe/calls/credential_repository.ex), [CredentialStore](../../apps/vxpipe_persistence/lib/vxpipe/persistence/credential_store.ex) | Store tenant identity and hash-only Vxpipe API keys. Provider encryption needs a separate concept and port; recoverable storage does not exist here today. |
| [PreparedCallFactory](../../apps/vxpipe_calls/lib/vxpipe/calls/prepared_call_factory.ex), [PreparedCallRecord](../../apps/vxpipe_persistence/lib/vxpipe/persistence/prepared_call_record.ex), [ResolvedPlanCodec](../../apps/vxpipe_persistence/lib/vxpipe/persistence/resolved_plan_codec.ex) | Compile, encode and reload complete plans. Keep secrets out and explicitly handle old serialized selections at cutover. |
| [PlanStartup](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/plan_startup.ex), [AgentActivation](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/plan_startup/agent_activation.ex), [AgentModel](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/plan_startup/agent_model.ex) (formerly `AgentModelProfile`) | Merge global private options, match `:req_llm`, and use profile IDs for usage/cache identity. Replace with tenant resolution and explicit provider/model/binding identity. |
| [ServiceRegistry](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/service_registry.ex), [ConfiguredService](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/configured_service.ex) | Store secret-bearing immutable carrier configurations and fall back from tenant service to application service. Replace hosted tenant lookup with DB service/credential resolution; remove the application credential fallback. |
| [Telnyx ServiceProfile](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/telnyx/service_profile.ex), [Twilio ServiceProfile](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/twilio/service_profile.ex) | Validate carrier-specific auth inputs and build adapter/verifier options. Retain this internal validation responsibility; obtain inputs from tenant records. These modules are not capability profiles. |
| [TelnyxEvents](../../apps/vxpipe_gateway/lib/vxpipe/gateway/http/telnyx_events.ex), [TwilioWebhookRequest](../../apps/vxpipe_gateway/lib/vxpipe/gateway/http/twilio_webhook_request.ex), [TwilioMedia](../../apps/vxpipe_gateway/lib/vxpipe/gateway/http/twilio_media.ex) | Fetch configured service before authentication. Twilio authenticates both webhooks and the WSS upgrade. Migrate all three boundaries, preserving verify-before-dispatch and verify-before-token-consumption. |
| [OutgoingLegConnector](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/outgoing_leg_connector.ex), [TelephonyAdmissions](../../apps/vxpipe_calls/lib/vxpipe/calls/telephony_admissions.ex) | Outbound selection has trusted tenant identity; inbound route lookup happens after verification. Both need tenant service validation without moving Repo into Gateway/Engine. |
| [TelephonyCallStore](../../apps/vxpipe_persistence/lib/vxpipe/persistence/telephony_call_store.ex), [telephony leg migration](../../apps/vxpipe_persistence/priv/repo/migrations/20260911103000_create_telephony_legs.exs) | Durable duplicate lookup/indexes use provider/service alias/event or leg ID without tenant. Scope queries and constraints to tenant and canonical service identity, not just live registries. |
| [MediaAdmission](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/media_admission.ex) | Token lookup currently consumes an entry or installs a waiter. Add bounded, non-consuming access to the existing leg's private initialized configuration before Twilio signature verification, including pending outbound reservations. |
| [TrustedCall](../../apps/vxpipe_gateway/lib/vxpipe/gateway/trusted_call.ex), [SampleCallBackend](../../apps/vxpipe_console/lib/vxpipe/console/sample_call_backend.ex), [dev.exs](../../config/dev.exs) | Supply profiles and bootstrap a fresh sample tenant. Remove profile inputs and make credential provisioning target the actual sample tenant before save. |
| [runtime.exs](../../config/runtime.exs) | Loads TOML into provider/global settings. Currently reads `VXPIPE_DATABASE_URL`, with a development URL from `dev.exs` and pool default 10. Replace that name/TOML pool input with the approved platform alias pairs and preserve env-free development. |

## Definition contract: upstream providers, no capability profiles

Introduce a new schema version with inline selections. Proposed fragment:

```json
{
  "defaults": {
    "capabilities": {
      "speech_to_text": {
        "provider": "deepgram",
        "model": "flux-general-en",
        "options": {
          "encoding": "opus",
          "sample_rate": 48000
        }
      },
      "model_inference": {
        "provider": "google",
        "model": "gemini-3.5-flash-lite",
        "options": {
          "temperature": 0.2
        },
        "provider_options": {
          "google_thinking_budget": 4096
        }
      }
    }
  }
}
```

The current parser accepts this shape under schema `20260915.01`. Google and Deepgram are the
initial hosted providers; verify additional model/option combinations as each provider slice lands.

- `provider` is the actual supported provider, such as `google` or `deepgram`.
  `provider: "req_llm"` and user-configurable adapter/module/transport fields are rejected.
- `model` is the provider-local identifier. The Google example becomes
  `google:gemini-3.5-flash-lite` only inside the integration. Router model paths such as
  `openai/gpt-5` remain intact; the existing Zenmux integration uses a Zenmux credential.
  Its inline migration is implemented with focused checks in checkpoint 5;
  see the [provider inventory](../existing-provider-credentials.md).
- `options` and `provider_options` contain supported non-secret data. Validate types,
  conflicts, bounds and supported combinations, then translate to the adapter's option shape.
  Neither object may replace credentials, provider/adapter identity, tool authority or protected
  transport policy. Provider options cannot redirect credential-bearing requests to arbitrary hosts.
- Optional `credential_name` selects a credential inside the tenant/provider scope; omission
  selects `default`. It never selects model/options. The earlier draft's `credential` key
  conflicts with the current private-material guard.
- Definition defaults provide reuse. A participant override replaces the complete selection for
  that capability kind, preventing options from one provider merging into another.
  `opening_audio.text_to_speech` has its own inline selection and still inherits no voice.
- The code-owned catalog maps capability kind/provider to the supported adapter, credential
  requirement and option/model validation. It never stores tenant secrets or model presets.
  Local Morse and explicitly test-only fixtures remain credential-free.
- Remove `capability_profiles`, profile-reference inputs and `CapabilitySelection.profile`
  from live selection. Keep host-tool and MCP registries, whose responsibilities are different.
  Update usage and cache identities using tenant/provider/model/options and a non-secret binding.

### Carrier selection and tenant service bindings

Carrier calls retain the existing provider-neutral `connection.service` intent, for example
`"service": "support-phone"`. A telephony service represents an account/connection, phone routing
and ingress binding; it is not an AI capability profile. Carriers do not acquire a `model` field.

Add tenant telephony service records and a Calls repository port. Each binds a stable service ID,
unique ingress key, `provider: "telnyx"` or `"twilio"`, exact account/connection identity,
credential reference, optional originating number and the existing carrier options needed by
current adapters. No new service-policy framework is required. Credentials and service must
belong to the same tenant and provider; enforce that at the database boundary.
The service references the stable credential identity; a new leg resolves its current active
version and supplies it to the existing leg configuration.
Public callback/media origins remain platform settings, with routes derived from the stored binding.

The call definition continues to carry phone intent, literal/protected-variable destination,
transfer permissions and media policy. Saving resolves every non-web connection service for its
tenant and requires active matching carrier credentials, including outbound transfer destinations.
There is no tenant-to-application carrier fallback. Pin non-secret service identity with prepared
calls; changing a service to a different provider/account must not silently reroute an old plan.
Distinguish the tenant-local service alias from the canonical DB service record identity. Carry
tenant and canonical service identity through durable admission claims, duplicate queries and
unique constraints as well as live correlation. Replayed provider event/leg IDs under matching
aliases in different tenants must never return another tenant's claim, including after restart.

## Credentials, authority and lifecycle

### Storage and ownership

- Add `provider_credentials` separately from Vxpipe-issued API keys. Include a non-null tenant FK,
  stable public ID, fixed provider, binding name, auth kind, encrypted payload, payload schema
  version, encryption key ID/version, credential version, lifecycle status and timestamps.
  Enforce tenant/provider/binding uniqueness.
- Encrypt recoverable payloads before persistence with authenticated encryption using an existing
  vetted facility or OTP crypto primitives. Bind tenant/provider/credential identity as associated
  authenticated data to detect ciphertext swapping. Keys come from the platform secret boundary,
  outside PostgreSQL. Specify nonce generation, key validation and stored-format versioning;
  no production default key. Platform encryption-key rotation is covered in checkpoint 6.
- Store Telnyx API keys and Twilio auth tokens in encrypted payloads. Store account/connection
  identifiers and verification public keys as controlled tenant metadata where needed for routing.
  Validate all provider authentication shapes before accepting a write.
- Calls owns neutral credential/service repository ports and trusted administration workflows.
  Persistence owns schemas, crypto-at-storage integration, transactions and adapters.
  Gateway owns carrier verification/control protocol; Agent Runtime owns ReqLLM translation.
- Call Engine owns a neutral runtime credential-source contract injected by its host; a Calls
  bridge implements it through repository ports. Engine has no Calls/Persistence dependency,
  Gateway has no Repo access, and Calls has no dependency on Gateway. Carrier configuration
  validation shared with Calls must remain data-only or be supplied through a neutral interface.
- The trusted operator CLI may target a tenant as existing local bootstrap does. Tenant-facing
  management APIs, if implemented, require that tenant's explicit admin grant. Ordinary
  call-scoped keys cannot manage credentials. Supply secrets by protected input/file descriptor,
  never command-line secret flags or echoed output. Responses expose metadata only.
- Vxpipe API keys remain SHA-256 digests. Their values cannot be recovered or used as provider keys.
  No secret/ciphertext enters definitions, plans, archives, inspection, routine logs or telemetry.

### Save, publish, prepare and activate

1. Parse and locally validate all effective participant selections, opening TTS and phone service
   requirements. Include transfer destinations, not just the initial caller/receiver.
2. Before inserting any definition/revision/routes, check the tenant's active credential records
   and required auth metadata. Missing, revoked, wrong-provider, unsupported auth kind or
   wrong-tenant bindings are hard save failures with path-specific safe errors. Local capabilities
   require none. Provider validation performs no network calls or token exchange.
3. Keep unrelated draft support errors under their existing rules only after credential
   requirements are fully determined. An unknown provider/service cannot bypass the credential gate.
   Preserve immutable revisions and test concurrent save/revoke ordering at the repository boundary.
4. Recheck at publication and preparation. Prepared plans store only selections and non-secret
   references. Revocation after save does not retroactively delete or rewrite revisions.
5. Resolve/decrypt at each new capability or carrier-leg activation, including opening, connection
   attachment and later transfers. Check active status and expected tenant/provider/account again.
   Use bounded preparation workers outside room-authority and media callbacks. Lookup/decryption
   failure starts no provider request; transfer failure preserves existing source-recovery behavior.

### Reader lifetime and unavailable storage

New capability/leg construction reads the selected tenant credential. An already constructed
provider client or admitted leg keeps its existing private configuration for its normal owned
lifetime. Moving the source to PostgreSQL must not add a database query to each media frame or
silently replace a running client's configuration.

Missing, inactive, wrong-tenant or undecryptable credentials fail closed when read; old environment
or application settings cannot rescue them. Test lookup failure separately from admission-store
failure, because an unavailable credential source must prevent a new provider request or dial.
Preserve existing admitted-leg callback/media/cleanup behavior using its initialized configuration.
Do not introduce a third-party credential rotation protocol, verification-key overlap registry
or refresh service.

### Authenticate carrier ingress before trusting tenant data

An ingress key resolves stored tenant/service metadata before examining a provider event as
trusted data. The URL locator is not authorization. Never select tenant credentials from an
unverified `AccountSid`, destination phone number, connection ID or arbitrary tenant parameter.

- Telnyx: verify exact raw body, Ed25519 signature and timestamp tolerance with that service's
  verification key; then check the provider connection and live leg identities.
- Twilio: verify form webhooks and media upgrade signatures against the exact configured public
  URL using that service's auth token; then check Account SID and call/stream identity. Signature
  failure must not consume a media token or dispatch a normalized event.
  Media reservations must retain access to the leg's initialized configuration before provider
  call binding completes. Use the existing leg/admission records; no separate authentication-lease
  subsystem is required. A bounded lookup by ingress key/token may locate that private
  configuration without consuming, extending expiry or registering a waiter. Verify first, then
  atomically consume against the same expected leg/service binding. Expired, replaced or
  mismatched bindings fail closed; unauthenticated callers cannot reserve/consume admission state
  or receive its private authentication material.
- For existing legs, unsigned correlation may only locate a candidate within the already selected
  service; verify its exact pinned credential/identity before dispatch. Never scan all tenant keys.
- Preserve duplicate/out-of-order handling, single-use media admission and existing no-redial
  semantics. Pin tenant/service in live registry/correlation keys wherever current service IDs
  alone would collide between tenants.

## Credential cutover checkpoints

Keep each credential-reader change, focused tests, relevant docs and labnotes in one usable
checkpoint. Use red-green-refactor for behavior changes. Reuse existing call-flow harnesses only
where necessary to prove the DB-to-adapter boundary; transfer readiness, cue playback, recovery,
bridging and media behavior remain owned by their existing milestones.

Keep schema cutover explicit: reject old profile inputs and document how to replace affected
local definitions/prepared calls through existing administration. Do not add a general legacy
profile conversion framework. Migrate in-repo fixtures and sample inputs with shared structures.

### Checkpoint 1 — Provision Google/Deepgram and run an inline tenant voice call

Depends on the implemented prerequisites above.

- [x] Write a failing workflow test: provision tenant Google/Deepgram credentials, save an inline
  definition, publish/prepare/join and exchange a synthetic voice turn. The same save for another
  tenant fails with no new revision/route. Test adapters observe only the expected credentials.
- [x] Deliver the minimum complete credential table/encryption, repository port, secret-source
  bridge and trusted provisioning/list-metadata operation required by this flow. Test ciphertext
  persistence, tenant isolation, unavailable keys and malformed payloads.
- [x] Introduce the inline schema and internal catalog with `google`/`deepgram`, common/provider
  option translation, local fixture exemption, and `req_llm`/profile-string rejection.
  Update the parser, compiler, plan representation and initial STT/LLM/TTS activation together.
- [x] Enforce hard save and fresh publish/prepare/activation checks for this flow. Preserve safe
  errors and prepared-plan secret exclusion. Keep Vxpipe API-key authentication unchanged.
- [x] Replace current profile-dependent consumers when changing the shared selection structure,
  including opening parser, usage/cache identity and trusted input. Migrate affected tests/sample
  definitions in this checkpoint so the umbrella compiles and the normal sample remains runnable.
- [x] Remove global/TOML/env credential reads and boot-time provider-key requirements for this
  delivered flow. Credentials are read after the Repo starts, through the tenant resolver.
- [x] Delete `VXPIPE_DEV_SPEECH_PROFILE` reads and both `speech_profile` switch branches in
  `config/runtime.exs`, plus obsolete launcher/sample/docs/test references. Select local Morse
  through the inline definition. Test that setting the retired variable cannot change the selected
  provider or activate a legacy fallback. Removing only the line from `env.sample` is insufficient.
- [x] Make Console sample setup select a stable provisioned development tenant through trusted
  operator setup; its call-scoped API key remains server-held. No startup import of provider env
  keys or copying a global secret into automatically created tenants.
- [x] Demonstrate from a disposable DB: provision → save → publish → prepare/join → spoken reply,
  plus missing/wrong-tenant credential and restart cases; record focused test commands/results.

Exit: one usable tenant voice call driven by inline provider/model selections and encrypted DB
credentials. Google is the public provider name. Implementation, tests and setup docs ship together.

### Checkpoint 2 — Finish AI and speech credential readers

Depends on checkpoint 1.

- [x] Inventory the existing opening, connection STT, agent activation, destination preparation,
  private briefing and source-restoration readers. Confirm each receives the host-injected tenant
  credential source; remove any remaining profile/global/env reader or merge.
  - [x] Record the [reader inventory](../credential-reader-boundaries.md) and independently review
    the planned construction paths.
  - [x] Remove reachable legacy `CreateRoom` global model/TTS/STT credential readers while
    preserving credential-free embedded operation.
- [x] Verify the opening reader with persisted tenant credentials, independent selection,
  tenant/binding cache isolation and rejection of an unavailable binding.
- [x] Add focused tests at remaining reader/adapter boundaries for the selected tenant/provider/name,
  whole-selection overrides and missing/wrong-tenant/inactive credential failure. Check that a
  later destination's missing binding blocks definition save before rows are written.
- [x] Verify a new activation reads the DB credential and lookup failure enters the existing
  preparation-failure path before any provider request. Reuse the existing source-failure contract.
  - [x] Resolve fresh source speech credentials before private briefing and source replacement;
    verify transport authentication and no new transport when the binding is unavailable.
- [x] Check that selections, cache identity, prepared plans and public error/history projections
  contain safe references, never credential payloads. Record the reader inventory and evidence.

Exit: every existing AI/speech construction path reads tenant DB credentials through the shared
boundary. No new transfer/recovery behavior or full round-trip audio demonstration is required.

### Checkpoint 3 — Move Telnyx credential readers to tenant storage

Depends on the credential store and existing Telnyx integration.

- [x] Add the tenant service record/port and trusted registration needed to locate existing Telnyx
  configuration. Bind tenant, provider, account/connection, ingress key and credential reference.
  Validate ownership and unique ingress keys; keep public callback/media origins platform-owned.
  Trusted OTP/CLI registration and metadata lookup are implemented; see [service storage](../tenant-telephony-services.md).
  Live credential readers remain pending.
  - [x] Provision named Telnyx API keys through the encrypted tenant store and protected-input
    operator CLI; verify tenant isolation, metadata-only output and invalid-payload rejection.
- [ ] Resolve matching tenant service credentials during definition save/publish/prepare and
  existing leg construction. Pin safe service identity so an old plan cannot change accounts.
  - [x] Resolve the exact active service credential privately; check every phone destination at
    save/publish/web preparation and hold the binding through the final database write. Incoming
    preparation shares preflight; its final insert guard, canonical plan binding and live leg
    construction remain pending. See [definition-guard evidence](../../labnotes/20260916-0057-telephony-credential-gates.md).
- [ ] Replace application/global service credential lookup for existing answer, dial, media and
  hangup commands. Verify the actual adapter receives only the selected tenant credential.
- [ ] Resolve webhook verification metadata from the stored ingress binding. Preserve raw-body,
  signature, timestamp, provider-connection and leg checks before dispatch.
- [ ] Keep durable and live service/leg lookup tenant-scoped when introducing tenant service
  records. Test matching aliases/provider IDs across tenants and persisted duplicate lookup.
- [ ] Test missing/wrong-tenant/inactive credentials and credential-source failure: no new request,
  admission or dial and no global fallback. Preserve initialized configuration for existing legs.
- [ ] Update provisioning/configuration documentation. Reuse targeted command/webhook tests;
  complete dialing, briefing, press-1, bridging and live audibility scenarios belong to the
  existing Telnyx milestone.

Exit: existing Telnyx command and authentication paths obtain their credentials/metadata from the
correct tenant DB records, with no application-scope credential fallback.

### Checkpoint 4 — Move Twilio credential readers to tenant storage

Depends on the common tenant service boundary from checkpoint 3 and the existing Twilio adapter.

- [ ] Add validated Twilio account SID/auth-token provisioning to the common service workflow.
  Reject wrong-provider, mixed auth fields and account/service mismatch.
- [ ] Migrate voice/status webhook and REST dial/hangup credential reads to the tenant records.
  Preserve the configured public signature URL and account/call/stream identity checks.
- [ ] Migrate WSS media authentication. Locate the existing leg/reservation's private configuration
  without consuming its token or installing a waiter before signature verification. Keep pending
  outbound reservations and exact token/binding consumption working with the selected tenant auth;
  extend existing leg/admission records instead of adding a separate authentication-lease subsystem.
- [ ] Test the actual signature and command boundaries with two tenants, missing/inactive bindings,
  wrong tokens/accounts and unavailable credential storage. Failed authentication consumes no token;
  no request uses application/global credentials.
- [ ] Verify tenant scope in durable/live duplicate lookup and preserve initialized configuration
  for existing legs. Reuse focused carrier tests and update setup documentation.

Exit: existing Twilio command, webhook and media-authentication readers use tenant DB credentials.
The original Twilio milestone's live-provider audibility gate remains separate.

### Checkpoint 5 — Preserve existing provider credential integrations

Depends on the shared credential source; keep changes in small provider-specific commits.

- [x] Inventory provider/auth/option paths supported by pre-cutover Vxpipe source and project
  tests. Neither installed SDK adapters nor website logos create new provider commitments.
  The interim Google-first catalog also does not justify dropping previously supported paths.
  Preserve demonstrated integrations and correct unsupported documentation claims. The
  [inventory](../existing-provider-credentials.md) identifies Google, Deepgram, Zenmux, Telnyx
  and Twilio with their existing API-key or Account SID/Auth Token shapes; Morse/fixtures need
  no credentials. Google/Deepgram are migrated, carrier readers have their own checkpoints,
  and Zenmux is the remaining model integration owned here. This inventory is not migration completion.
- [x] Supply each existing model/speech adapter's current auth shape from the selected tenant record.
  Validate malformed/mixed inputs before requests. New provider/auth-mode support, OAuth
  onboarding/refresh and arbitrary credential-file discovery are outside this checkpoint.
- [x] Verify actual adapter request construction with focused doubles: tenant/provider/name,
  model/options, nested options and existing router model paths. Preserve current validation,
  provider identity and protected transport settings.
- [x] Seed conflicting ambient credentials for the existing integrations and prove they are
  never used. Unsupported provider/auth combinations remain rejected; no new integration is
  required to exercise this isolation rule.
- [x] Update affected provider setup pages and option links. Mark genuinely unsupported
  combinations honestly; do not expand model/provider functionality as part of this cutover.

The remaining model integration is implemented and its credential-reader exit is verified.
Independent implementation review found no production blocker; its application-auth fixture
correction is verified. The full root run completed 1,547 tests with one previously reproduced
native Morse failure and 33 exclusions. Format, compile, strict Credo and unused-lock checks pass.
The common umbrella gate remains open; that failure does not add an audio requirement to this
credential-reader checkpoint. Final independent gate review confirmed this distinction.
Telnyx/Twilio reader completion remains owned by checkpoints 3 and 4.

Follow-up review found an outer startup gate missed by the initial constructor tests: it still
rejected Zenmux entry agents. The gate now accepts the existing integration, and a public room-startup
regression reproduces the original failure and verifies preparation with the named tenant key.
See [startup correction evidence](../../labnotes/20260916-0118-zenmux-room-startup.md).

Exit: existing supported provider integrations read explicit tenant credentials and retain their
public inline selection/options contract, with no SDK ambient credential fallback.

### Checkpoint 6 — Rotate the platform-owned encryption key

Depends on the encrypted credential store from checkpoint 1. The platform operator controls the
encryption key; tenant/provider API-key values are unchanged by this operation.
Reuse the existing `CredentialKeyring` and `CredentialCipher`: they already select an externally
supplied active write key and locate decrypt keys by stored key ID. New writes keep using the
active key, and no key is stored in PostgreSQL. This checkpoint adds the re-encryption operation
and its transition evidence, not another key-provider framework.

- [ ] Provide a bounded, resumable re-encryption operation that decrypts each existing payload and
  encrypts the same value under the active key, preserving tenant/provider/credential identity.
  Keep secret values and ciphertext out of command output and logs.
- [ ] Verify interruption/retry and concurrent credential writes cannot lose or misassign payloads.
  Report safe progress and remaining key IDs so the operator can determine when an old key is unused.
- [ ] Verify a disposable DB across restart: old/new rows decrypt during transition; after complete
  re-encryption, removing the old key still permits all credential reads. Missing/wrong keys fail
  closed. Confirm the plaintext third-party credentials are unchanged.
- [ ] Document key provisioning, re-encryption and old-key retirement. Do not add external-provider
  API-key rotation, callback-token overlap or requirements on tenants' credential schedules.

Exit: the platform operator can replace the encryption key protecting stored secrets and retire
the old key after verified re-encryption, without changing any third-party credential.

### Checkpoint 7 — Finish platform configuration and remove old readers

Depends on the credential-reader checkpoints above. This is the final operational cutover and acceptance slice.
Audit existing checkpoint evidence against the final source. Reuse valid privacy, no-fallback,
isolation and restart checks; add focused tests only for changed or uncovered boundaries.

- [ ] Verify startup/configuration loading with platform env settings and pre-provisioned tenant
  credentials. A provider construction smoke check proves the DB source after restart; do not
  repeat complete voice/phone/artifact lifecycle scenarios from other milestones.
- [ ] Remove remaining TOML loader/`VXPIPE_CONFIG`, `vxpipe.toml.sample`, global provider
  credential configuration and unused `apps/vxpipe_config`/TOML dependencies. Update exact child
  dependencies and lockfile entries. Runtime normalization needed by adapters stays with its owner.
  The user deleted the uncommitted app before implementation; the preparatory cleanup removes
  its dangling consumers now. Final acceptance must still audit their absence. ReqLLM’s
  `llm_db` dependency requires its own TOML parser; it is not a platform config loader.
- [ ] Audit and delete every superseded provider configuration entry point, reader, merge and
  fallback branch, including `provider_api_key_environment`, global provider model/options and
  application-scope carrier configuration. Remove obsolete settings from docs/examples and
  reject removed public configuration fields; retain no compatibility switch or dormant path.
- [ ] Prove absence of fallback: populate conflicting old provider env/application settings and a
  legacy config file in isolated tests. Without an active tenant DB credential, save/preparation/
  activation must fail with no provider request. With one, only that credential and the definition
  options are used; the old file is never read and SDK ambient discovery is never invoked.
- [ ] Restore and catalog platform database/pool, S3, listener/TLS, callback origin and encryption
  settings in `config/runtime.exs` and `env.sample` (keep `.env.example` synchronized or retire
  the duplicate). Add concise comments, mandatory placeholders, and commented optional variables.
  Verify launcher/Console/Astro wiring only where this configuration cutover changes it;
  no provider secret is required before tenant DB provisioning.
- [x] Configure recordings and call-details publication from the same `STORAGE_BUCKET`,
  `AWS_REGION`, `AWS_ENDPOINT` and AWS credential settings. Remove both old S3 setting families and their fallback rules from
  runtime, samples and current operational docs. Test that both writers use the same bucket,
  region and endpoint, and that conflicting retired values cannot select another destination.
  Cover unset, blank, invalid and retired-only settings, preserving independent recording enablement
  and current publication enablement. An enabled writer cannot silently lose its required bucket.
- [ ] Implement the database contract: `VXPIPE_DB_URL` before `DATABASE_URL`, and
  `VXPIPE_DB_POOL_SIZE` before `DB_POOL_SIZE`; default development to `vxpipe_dev` and pool 10
  without database env requirements. Retire `VXPIPE_DATABASE_URL` and update CLI diagnostics,
  setup/provider-operation docs, examples and affected configuration/launcher tests together.
- [ ] Add focused runtime-configuration cases for each alias alone, both with conflicting values,
  unset/blank values, invalid selected URL/pool values, the retired name alone and test-database
  isolation. Demonstrate development boot/provision/prepare using the default local database/pool
  with all four database env vars unset; verify non-development never defaults to `vxpipe_dev`.
- [ ] Document replacement of old profile-based definitions/prepared calls using existing
  administration. Keep old-plan activation rejected and immutable history intact. Add a migration
  only for a demonstrated persisted-data requirement; no generic profile-conversion framework.
- [ ] Update architecture, tenant operations, developer/provider docs and the container delivery
  specification. Environment plus tenant DB replaces the proposed deployment JSON/TOML loader;
  JSON call definitions remain. Preserve embedded fixture/local-provider use without Ecto.
- [ ] Obtain the requested independent agent review of the final implementation, fix findings,
  then run all five common root gates once the reviewed checkpoint is ready. Record exact results.
- [ ] Confirm existing evidence covers two-tenant persistence, unavailable/wrong encryption keys,
  safe failure projections and restart at the final credential/configuration boundary; fill only
  uncovered gaps. Platform encryption-key rotation is
  covered in checkpoint 6; upstream credential rotation, backup drills and full carrier audibility
  acceptance are outside this milestone.
- [ ] Validate source-development/macOS boot now. Verify packaged/container boot only after the
  separate delivery milestone's hold is released; do not claim or require a not-yet-built image.
- [ ] Update the checkpoint evidence ledger, milestone index and labnotes. Leave this milestone
  unchecked for any unresolved acceptance gate; no commits unless requested.

Exit: documented setup and restart load platform env settings and construct tenant-bound providers
from encrypted storage using inline selections, with all obsolete live configuration paths removed.
The existing tenant-call evidence remains valid; another full call demonstration is not required.
Container publishing remains governed by its separate milestone.

## Acceptance matrix

Each row verifies a changed credential/configuration boundary. Existing call-flow regression tests
remain part of the umbrella suite; this matrix does not create a second call-flow milestone.
Map rows to existing valid evidence before adding tests or manual demonstrations.

| Boundary | Required evidence |
| --- | --- |
| Inline selection | Actual provider/model and supported options select internal adapters; retired profiles/public adapter fields reject. |
| Save/publish/prepare | Every effective requirement, including later destinations, resolves for the tenant before a write; missing/wrong-tenant/inactive bindings fail safely. |
| AI/speech construction | Opening, connection, agent, destination, briefing and restoration readers use the injected DB source; actual adapters receive the exact selected credential. |
| Telnyx | Existing commands and webhook verification use matching tenant credentials/metadata; invalid auth or unavailable credentials produce no dispatch/request. |
| Twilio | Existing REST, webhook and WSS boundaries use matching tenant auth; failed authentication consumes no media token or waiter. |
| Tenant service isolation | Live and persisted lookups cannot cross tenants with matching aliases or provider event/leg IDs. |
| Reader failure | Missing/undecryptable/inactive credentials fail before new provider work; existing initialized clients retain their normal owned lifetime. |
| Persistence/privacy | Recoverable credentials are encrypted; Vxpipe API keys remain hash-only; definitions, plans, archives, inspection and logs exclude credential payloads. |
| Encryption-key rotation | Re-encryption and restart preserve the exact tenant credential values; verified completion permits removal of the old platform key. |
| Platform env | Database/S3/HTTP/key settings load from env; required placeholders and commented optional settings appear in visible `env.sample`. |
| Database aliases | Approved precedence/defaults, invalid-value failure and test-database isolation hold. |
| Removed readers | No provider env/application/TOML/profile fallback, SDK ambient discovery or obsolete `apps/vxpipe_config` consumer remains. |

## Scope and rejected alternatives

- Rotating/revoking third-party credentials, backup/restore drills, carrier verification-key overlap,
  OAuth lifecycle work and broad transfer/recovery demonstrations are excluded. Existing
  inactive-status validation remains part of safe reads. Platform-owned encryption-key rotation
  is included; it changes the storage protection, not the third-party credential values.
- This includes tenant credentials for hosted AI/speech and Telnyx/Twilio. It does not move
  platform S3 credentials to tenant storage or introduce platform-shared provider accounts.
- Capability profiles and public adapter fields are removed. Definition defaults supply reuse;
  a new preset/template system is not required.
- Carrier service bindings retain routing/account semantics. Internal carrier `ServiceProfile`
  validators may remain or be renamed for clarity; they must not become user-configured model
  profiles or a back door to global credentials.
- Definition save does not call providers, exchange tokens, or promise that credentials will remain
  usable upstream. It verifies local requirements; activation handles later failure explicitly.
- No general OAuth onboarding, arbitrary secret-file reads, cross-provider fallback, automatic
  redial, new telephony protocol or unrelated MCP credential migration is included.
- No new management UI is needed. Trusted provisioning plus metadata inspection must support
  setup; rendered verification applies if the cutover actually changes UI behavior.
- Existing transfer/recovery/media behavior stays in its owning milestones. Fix a regression
  introduced by the cutover; unrelated defects and enhancements are separate work.

## Preparatory worktree cleanup

- [x] Review the dirty worktree before implementation and discard the superseded TOML/global
  provider additions with their dependencies and tests; preserve unrelated website work.
- [x] Independently review cleanup with GPT 6 Astra xhigh. The auth additions also allowed local
  credential-file paths and mixed Bedrock auth. Retain those findings as historical evidence;
  add regression cases only if they apply to an integration retained by checkpoint 5's inventory.
- [x] Run the restored umbrella gates and record baseline results in the cleanup labnote.
  Static root gates and launcher/build checks pass. The full suite ran 1,436 tests with one
  existing native human-handoff timeout; that exact case passed in isolation without source
  changes. The cause remains unresolved and final umbrella acceptance remains unchecked.
  The docs suite also retains a pre-existing badge assertion mismatch.

This restores the committed runtime as the implementation baseline. Its old provider env/profile
paths remain to be replaced by the owning vertical slices; cleanup alone completes no call flow.
The [cleanup labnote](../../labnotes/20260915-1600-tenant-credential-storage.md) records exact
scope, independent review, root/isolated test evidence and rendered homepage checks.

## Evidence ledger

Current progress: **3 of 7 complete** (checkpoints 1, 2 and 5), **2 partial** (checkpoints 3 and 7),
and **2 not started** (checkpoints 4 and 6). Implementation boxes stay unchecked until their runnable
exits and failure cases pass.

| Checkpoint | Implementation | Focused/flow evidence |
| --- | --- | --- |
| 1 — Tenant voice call | Implemented and verified; inline schema/runtime cutover ships with its consumers and fixtures | 19 focused database/integration checks pass, including a synthetic Google/Deepgram reply and transaction ordering. Browser preparation/restart checks pass. All five root gates pass: 1,489 tests, zero failures, 30 excluded (seed 235296). A discovered destination-progress bug was fixed separately. Earlier intermittent native audio/cleanup observations remain documented; this green run does not establish their cause. Final independent review remains open after a reviewer usage limit. See [inline evidence](../../labnotes/20260915-1719-inline-tenant-voice.md) and [provisioning evidence](../../labnotes/20260915-1616-tenant-credential-provisioning.md). |
| 2 — AI/speech credential readers | Implemented and verified | Opening, connection, briefing and source-restoration readers use fresh tenant resolution; legacy global readers are removed. Destination save validation covers missing/wrong-tenant/inactive model/TTS/STT bindings before writes; the Persistence group passes 18 tests (2 excluded). Named tenant isolation, whole-selection overrides and fresh construction pass 15 Engine tests. Three tagged local DB activation tests verify current Google/Deepgram authentication and safe failure before requests. Independent GPT 6 Astra xhigh review found no blockers. All five root gates pass: 1,532 tests, zero failures, 33 excluded (seed 235296). A native test assertion found in the initial run was corrected in a separate reviewed commit; its focused case and the full Gateway suite pass. Live provider checks remain excluded. See the [reader inventory](../credential-reader-boundaries.md), [destination evidence](../../labnotes/20260915-2250-destination-credential-boundaries.md), [native assertion correction](../../labnotes/20260915-2317-native-readiness-assertion.md), [global-reader evidence](../../labnotes/20260915-2223-remove-global-readers.md), [opening evidence](../../labnotes/20260915-2039-tenant-opening-credentials.md) and [source-reader evidence](../../labnotes/20260915-2203-audit-credential-readers.md). |
| 3 — Telnyx credential readers | Encrypted provisioning and trusted service storage verified; live readers pending | Named Telnyx keys use the existing encrypted store and protected-input CLI with the existing carrier key-size limit. Focused red/green: 14 tests, zero failures after the change. Calls 81 and Persistence 89 tests pass (6 excluded); format, compile and strict Credo pass. Independent GPT 6 Astra xhigh review found no code blocker; a transitional documentation claim was corrected. All five root gates pass for provisioning: 1,534 tests, zero failures, 33 excluded (seed 235296). Trusted service registration/lookup adds 8 passing focused checks, with Calls 81 and Persistence 95 tests passing (6 excluded). The operator CLI adds 3 passing focused tests; all 98 Persistence tests pass (6 excluded). Static root gates and independent review pass. Full root run: 1,543 tests, one native WebRTC Morse-decoding failure, 33 excluded; the unchanged isolated case reproduces. Live readers and full umbrella acceptance remain pending. See [service evidence](../../labnotes/20260916-0000-tenant-telephony-services.md). See [service storage](../tenant-telephony-services.md) and [Telnyx provisioning evidence](../../labnotes/20260915-2341-telnyx-credential-provisioning.md). |
| 4 — Twilio credential readers | Not started | Pending |
| 5 — Existing provider credential integrations | Implemented; credential-reader exit verified | Named API-key provisioning, inline model/options translation, tenant startup resolution and native routing use the existing adapters. Agent Runtime 5, Engine constructor 5 and Persistence focused 33 tests pass (2 excluded). Independent GPT 6 Astra xhigh review found no production blocker; its application-auth fixture correction is verified by the 95-test Agent Runtime suite (4 excluded). Calls 81 and Persistence 99 tests pass (6 excluded). All static gates and unused-lock checks pass. The full root run completed 1,547 tests with one previously reproduced native Morse failure and 33 exclusions; common milestone acceptance remains open. Independent gate review confirms the focused checkpoint exit is satisfied. No new provider or auth-mode support is added. See the [inventory](../existing-provider-credentials.md) and [Zenmux evidence](../../labnotes/20260916-0033-zenmux-tenant-credentials.md). |
| 6 — Platform encryption-key rotation | Not started | Pending |
| 7 — Platform configuration and cleanup | Shared artifact bucket implemented; remaining cutover pending | Both writers, playback and recovery share the unprefixed storage settings; retired settings cannot override or rescue them. Focused red/green, temporary-credential resolution and independent review pass. All five root gates pass: 1,459 tests, 0 failures, 16 excluded. See [shared-bucket evidence](../../labnotes/20260915-1656-shared-artifact-bucket.md). |

- [ ] Verify every credential/configuration boundary and checkpoint exit above.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates)
  after independent implementation review.
- [ ] Update this milestone, index and related documentation with actual implementation evidence.

Checkpoint 3 definition-guard follow-up: private exact service resolution and final
save/publish/web-preparation guards pass 13 focused database tests, Calls 81 and Persistence 106
tests (6 excluded), root static gates and independent GPT 6 Astra xhigh review. Incoming admission
shares preflight only; its final insert guard, canonical plan references and live readers remain
pending. Checkpoint 3 stays partial. The full root run at `a21ba3f` completes 1,554 tests with the
same native Morse assertion failure and 33 exclusions; unused-lock checks pass. Common umbrella
acceptance remains open. See [guard evidence](../../labnotes/20260916-0057-telephony-credential-gates.md).

## Specification review

Follow-up scope audit (2026-09-15): independent GPT 6 Astra xhigh and local source review found
remaining overbreadth in unconditional provider/auth examples, prescribed carrier machinery and
duplicate acceptance work. Restricted checkpoint 5 to demonstrated pre-cutover support; retained
existing carrier options/private leg configuration and the existing keyring; narrowed final checks
to changed or uncovered boundaries. Tenant/service isolation, authentication-before-consumption,
encryption-key re-encryption and configuration cleanup remain required. This documentation change
completed no checkpoint; at that audit, progress was 2 complete, 1 partial and 4 not started. See the
[audit evidence](../../labnotes/20260915-2333-remaining-credential-scope.md).

Scope correction (2026-09-15): local review traced the user's DB-reader clarification against every
checkpoint. Removed third-party credential lifecycle feature work, narrowed existing-flow acceptance
to credential boundaries and retained tenant isolation/authentication/no-fallback requirements.
A subsequent user clarification explicitly retains platform-owned encryption-key rotation.
The seven-checkpoint count remains; scope and implementation evidence are distinct. No new runtime
code is included in this scope commit. The independent review history below applies to the earlier
specification; final independent implementation review remains pending after the reviewer usage limit.

Local source review on 2026-09-15 traced profile selection, provider startup, prepared-plan
encoding, tenant administration, carrier service fallback, webhook/WSS authentication, outbound
leg resolution and sample bootstrap. This review changed the draft from layer-based tasks to
complete call/operator flows and added tenant telephony service lookup before ingress verification.

Agent review by Lorentz on 2026-09-15 identified three missing telephony contracts: durable
tenant-scoped deduplication, non-consuming access to Twilio's initialized leg authentication, and
separate credential versus admission-storage outage tests. Each is now specified in the carrier contracts, owning
checkpoints and acceptance matrix. Bounded re-review reported no remaining blocking findings
or vertical-order contradiction. This is specification review, not runtime implementation approval.
The later explicit-deletion clarification and platform removal/negative-test tasks also
received bounded agent review with no blocking findings; no alternate configuration path is retained.
The database alias/default contract and its platform configuration tasks received bounded agent review
against current runtime/development/test configuration, with no blocking findings or order change.
The explicit speech-profile reader deletion and shared artifact bucket tasks received independent
review on 2026-09-15. The review confirmed their dependency order and added missing/blank/invalid/
retired-only bucket cases plus enablement preservation. That specification review preceded
implementation; the shared-bucket implementation evidence is recorded above. Inline speech-profile
reader deletion and conflicting-old-settings tests are implemented in checkpoint 1.

Initial specification documentation checks passed: 131 relative links/anchors across this milestone and the index,
one parsed JSON example, seven sequential checkpoints with exits, 61 unchecked tasks, and index
counts of 26 entries/21 implemented. `git diff --check` passed. No full test suite was run for
that documentation-only change; subsequent implementation evidence is recorded in the ledger.
