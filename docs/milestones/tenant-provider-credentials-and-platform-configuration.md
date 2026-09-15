# Tenant-scoped provider credentials and platform configuration

Status: specification requested 2026-09-15; implementation not started.
The user approved removing capability profiles, keeping ReqLLM internal, and including
Telnyx/Twilio credentials. Agent specification review is complete; implementation remains unchecked.

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
| Credential encryption key/key-provider configuration | Platform secret supplied outside PostgreSQL |
| ReqLLM, provider modules, transport modules | Internal implementation selected by closed code-owned catalogs |

Amazon Bedrock credentials are tenant credentials even when platform S3 also uses AWS credentials.
An absent Bedrock credential must never fall through to the platform's AWS environment.
Telnyx's webhook public key is verification metadata, not a private signing key; associate it with
the tenant service and version it with the authentication configuration.

This decision supersedes [Runtime TOML configuration](../runtime-toml-configuration.md) and the
older proposed deployment-config-file contract. Definition JSON remains the portable behavior
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

## Code review baseline and change map

These observations are from the current source, including uncommitted TOML work.

| Reviewed code | Current behavior and required change |
| --- | --- |
| [Capabilities](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_definition/capabilities.ex), [OpeningAudio](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_definition/opening_audio.ex) | Parse profile strings. Replace them with inline selections in defaults, participant overrides and independent opening TTS. |
| [DefinitionCompiler](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/definition_compiler.ex), [CapabilitySelection](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/call_definition/capability_selection.ex) | Resolve a required `capability_profiles` registry and retain `profile`. Remove that lookup/field and separate public provider identity from adapter identity. |
| [Definitions](../../apps/vxpipe_calls/lib/vxpipe/calls/definitions.ex) | Saves unsupported catalog references as draft validation errors; publishing checks the stored errors only. Add hard credential gates before save and fresh checks at publication/preparation. |
| [PrivateMaterial](../../apps/vxpipe_calls/lib/vxpipe/calls/private_material.ex) | Rejects keys such as `credential`, `api_key`, and `token`. Add a typed non-secret reference without weakening payload rejection. |
| [CredentialRepository](../../apps/vxpipe_calls/lib/vxpipe/calls/credential_repository.ex), [CredentialStore](../../apps/vxpipe_persistence/lib/vxpipe/persistence/credential_store.ex) | Store tenant identity and hash-only Vxpipe API keys. Provider encryption needs a separate concept and port; recoverable storage does not exist here today. |
| [PreparedCallFactory](../../apps/vxpipe_calls/lib/vxpipe/calls/prepared_call_factory.ex), [PreparedCallRecord](../../apps/vxpipe_persistence/lib/vxpipe/persistence/prepared_call_record.ex), [ResolvedPlanCodec](../../apps/vxpipe_persistence/lib/vxpipe/persistence/resolved_plan_codec.ex) | Compile, encode and reload complete plans. Keep secrets out and explicitly handle old serialized selections at cutover. |
| [PlanStartup](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/plan_startup.ex), [AgentActivation](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/plan_startup/agent_activation.ex), [AgentModelProfile](../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/plan_startup/agent_model_profile.ex) | Merge global private options, match `:req_llm`, and use profile IDs for usage/cache identity. Replace with tenant resolution and explicit provider/model/binding identity. |
| [ServiceRegistry](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/service_registry.ex), [ConfiguredService](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/configured_service.ex) | Store secret-bearing immutable carrier configurations and fall back from tenant service to application service. Replace hosted tenant lookup with DB service/credential resolution; remove the application credential fallback. |
| [Telnyx ServiceProfile](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/telnyx/service_profile.ex), [Twilio ServiceProfile](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/twilio/service_profile.ex) | Validate carrier-specific auth inputs and build adapter/verifier options. Retain this internal validation responsibility; obtain inputs from tenant records. These modules are not capability profiles. |
| [TelnyxEvents](../../apps/vxpipe_gateway/lib/vxpipe/gateway/http/telnyx_events.ex), [TwilioWebhookRequest](../../apps/vxpipe_gateway/lib/vxpipe/gateway/http/twilio_webhook_request.ex), [TwilioMedia](../../apps/vxpipe_gateway/lib/vxpipe/gateway/http/twilio_media.ex) | Fetch configured service before authentication. Twilio authenticates both webhooks and the WSS upgrade. Migrate all three boundaries, preserving verify-before-dispatch and verify-before-token-consumption. |
| [OutgoingLegConnector](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/outgoing_leg_connector.ex), [TelephonyAdmissions](../../apps/vxpipe_calls/lib/vxpipe/calls/telephony_admissions.ex) | Outbound selection has trusted tenant identity; inbound route lookup happens after verification. Both need tenant service validation without moving Repo into Gateway/Engine. |
| [TelephonyCallStore](../../apps/vxpipe_persistence/lib/vxpipe/persistence/telephony_call_store.ex), [telephony leg migration](../../apps/vxpipe_persistence/priv/repo/migrations/20260911103000_create_telephony_legs.exs) | Durable duplicate lookup/indexes use provider/service alias/event or leg ID without tenant. Scope queries and constraints to tenant and canonical service identity, not just live registries. |
| [MediaAdmission](../../apps/vxpipe_gateway/lib/vxpipe/gateway/telephony/media_admission.ex) | Token lookup currently consumes an entry or installs a waiter. Add bounded, non-consuming private auth-lease discovery before Twilio signature verification, including pending outbound reservations. |
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

This fragment illustrates the target schema; the current parser does not accept it. Verify actual
model/option combinations against the installed adapters as each provider slice is implemented.

- `provider` is the actual provider: `google`, `deepgram`, `openai`, etc.
  `provider: "req_llm"` and user-configurable adapter/module/transport fields are rejected.
- `model` is the provider-local identifier. The Google example becomes
  `google:gemini-3.5-flash-lite` only inside the integration. Router model paths such as
  `openai/gpt-5` remain intact; `provider: "openrouter"` requires an OpenRouter credential.
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
credential reference, optional originating number and allowed service policy. Credentials and
service must belong to the same tenant and provider; enforce that at the database boundary.
The service references the stable credential identity; a new leg resolves its current active
version and pins that version privately. Rotation does not require republishing the definition.
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
  outside PostgreSQL. Specify nonce generation, key validation, versioning and rotation in the
  first slice; no production default key.
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

### Rotation, revocation and database outages

A new activation/leg uses the current active credential version. Existing provider configurations
and admitted carrier legs hold a private snapshot for their bounded lifetime; rotation does not
silently swap credentials mid-request or mid-leg. Revocation blocks new save/publish/prepare and
resolution. It is not an automatic termination of established calls.

Known live carrier callbacks, media-token completion and final cleanup must be verifiable with the
leg's pinned identity/configuration without a fresh database dependency. New admissions, new legs,
and credential acquisition fail closed on database/key-provider outage. Established media and
permitted cleanup continue; no global provider fallback or credential cache shared across tenants.
Keep credential-source/key failure distinct from an admission-store-only failure in tests. The
existing carrier harness can disable admission persistence while still dialing transfers; that
does not prove behavior when new credential resolution itself is unavailable. An admission-only
outage may preserve existing transfer behavior when credentials are independently available.

Define bounded version overlap for carrier callback verification during rotation, limited to the
exact tenant/service and admitted leg. Retire old verification material with its final lease.
No old version authorizes a new incoming call after revocation. If the carrier invalidates a token
upstream, report cleanup/auth failure honestly; never retry or switch accounts speculatively.

### Authenticate carrier ingress before trusting tenant data

An ingress key resolves stored tenant/service metadata before examining a provider event as
trusted data. The URL locator is not authorization. Never select tenant credentials from an
unverified `AccountSid`, destination phone number, connection ID or arbitrary tenant parameter.

- Telnyx: verify exact raw body, Ed25519 signature and timestamp tolerance with that service's
  verification key; then check the provider connection and live leg identities.
- Twilio: verify form webhooks and media upgrade signatures against the exact configured public
  URL using that service's auth token; then check Account SID and call/stream identity. Signature
  failure must not consume a media token or dispatch a normalized event.
  Media reservations must retain an auth-lease reference before provider call binding completes.
  A bounded lookup by ingress key/token may locate that private pinned lease without consuming,
  extending expiry or registering a waiter. Verify first, then atomically consume against the
  same expected lease/binding. Expired, replaced or mismatched leases fail closed; unauthenticated
  callers cannot reserve/consume admission state or receive its private authentication material.
- For existing legs, unsigned correlation may only locate a candidate within the already selected
  service; verify its exact pinned credential/identity before dispatch. Never scan all tenant keys.
- Preserve duplicate/out-of-order handling, single-use media admission and existing no-redial
  semantics. Pin tenant/service in live registry/correlation keys wherever current service IDs
  alone would collide between tenants.

## Vertical implementation checkpoints

Each checkpoint must end with the stated operator/caller flow working, including implementation,
focused tests, relevant docs and labnotes. Storage, schema and runtime work belong together within
a slice; they are not separately completed milestones. Use red-green-refactor from the owning
child. Run full umbrella tests after independent review, as requested, not after every edit.

Checkpoint demonstrations use isolated, provisioned state. A changed selection schema must not
be deployed over old persisted plans before their explicit cutover: keep the prior deployment
running until checkpoint 7's revision conversion and prepared-call drain are ready. Converted
paths have no dual-read profile/global-credential fallback. Migrate affected in-repo fixtures and
sample inputs when changing shared structures, not at the final cleanup checkpoint.

### Checkpoint 1 — Provision Google/Deepgram and run an inline tenant voice call

Depends on the implemented prerequisites above.

- [ ] Write a failing workflow test: provision tenant Google/Deepgram credentials, save an inline
  definition, publish/prepare/join and exchange a synthetic voice turn. The same save for another
  tenant fails with no new revision/route. Test adapters observe only the expected credentials.
- [ ] Deliver the minimum complete credential table/encryption, repository port, secret-source
  bridge and trusted provisioning/list-metadata operation required by this flow. Test ciphertext
  persistence, tenant isolation, unavailable keys and malformed payloads.
- [ ] Introduce the inline schema and internal catalog with `google`/`deepgram`, common/provider
  option translation, local fixture exemption, and `req_llm`/profile-string rejection.
  Update the parser, compiler, plan representation and initial STT/LLM/TTS activation together.
- [ ] Enforce hard save and fresh publish/prepare/activation checks for this flow. Preserve safe
  errors and prepared-plan secret exclusion. Keep Vxpipe API-key authentication unchanged.
- [ ] Replace current profile-dependent consumers when changing the shared selection structure,
  including opening parser, usage/cache identity and trusted input. Migrate affected tests/sample
  definitions in this checkpoint so the umbrella compiles and the normal sample remains runnable.
- [ ] Remove global/TOML/env credential reads and boot-time provider-key requirements for this
  delivered flow. Credentials are read after the Repo starts, through the tenant resolver.
- [ ] Make Console sample setup select a stable provisioned development tenant through trusted
  operator setup; its call-scoped API key remains server-held. No startup import of provider env
  keys or copying a global secret into automatically created tenants.
- [ ] Demonstrate from a disposable DB: provision → save → publish → prepare/join → spoken reply,
  plus missing/wrong-tenant credential and restart cases; record focused test commands/results.

Exit: one usable tenant voice call driven by inline provider/model selections and encrypted DB
credentials. Google is the public provider name. Implementation, tests and setup docs ship together.

### Checkpoint 2 — Open, transfer and return with independently selected providers

Depends on checkpoint 1.

- [ ] Write failing end-to-end cases for independent opening TTS, human entry, agent transfer,
  human transfer/briefing and source recovery with tenant credentials and whole-selection overrides.
- [ ] Complete credential resolution for opening TTS, caller connection STT, destination model/
  speech construction, private briefing and subsequent participant activation. Preserve deadlines,
  waits/readiness, cue-before-conversation, source continuity and local Morse operation.
- [ ] Block definition save when any effective transfer destination or opening selection lacks its
  credential, even when the entry participants are fully configured.
- [ ] Verify an unavailable destination credential during transfer preserves the source; no secret
  enters transfer context/history, usage, cached audio identity or inspection. Cache identity remains
  tenant/provider/model/options/binding scoped without including secret bytes.
- [ ] Exercise source → destination → source with deterministic media and provider doubles;
  document the exact working definition and render the existing sample if its UI behavior changes.

Exit: the existing opening and transfer flows use inline selections and tenant credentials across
their full lifecycle, with audible recovery on a controlled destination preparation failure.

### Checkpoint 3 — Receive a Telnyx call and transfer to a phone using tenant credentials

Depends on checkpoints 1–2 and the implemented Telnyx adapter.

- [ ] Write a failing two-tenant scenario: provision Telnyx auth, register a tenant phone service,
  save/publish a phone definition, accept a signed incoming call, then dial/brief/accept/bridge a
  destination and hang up using only the tenant DB credential.
- [ ] Add the tenant telephony service table/port and trusted registration workflow in this slice.
  Bind ingress key, service ID, provider connection, originating number, verification public key
  and stable credential reference. Pin the resolved credential version per leg; enforce
  tenant/provider ownership and unique ingress keys.
- [ ] Extend definition save/publish/prepare validation to non-web services, including outgoing
  destinations. Pin safe account/service identity in plans; reject retargeting behind a prepared call.
- [ ] Migrate durable telephony claim queries and unique constraints to tenant/canonical service
  identity, including explicit backfill validation for existing rows. Exercise matching service
  aliases and repeated provider event/leg IDs across tenants, replay and database reload/restart;
  no lookup may return another tenant's claim or suppress its legitimate admission.
- [ ] Replace Telnyx `ServiceRegistry` secret snapshots for new admissions/legs with tenant
  resolution. Remove application-scope credential fallback. Retain internal provider validators
  and platform callback/media origins; no public adapter field is added.
- [ ] Authenticate Telnyx ingress from the registered ingress key, then verify raw-body signature,
  timestamp, connection and leg correlation before Calls admission. Resolve command credentials
  for answer, dial, media start/stop and end-call at the appropriate leg boundary.
- [ ] Test unknown ingress, invalid signature, wrong connection/provider/tenant, missing/revoked
  credential and storage outage before admission. No case may dispatch an event or submit a dial.
- [ ] Prove duplicate callbacks do not recreate/redial; an admitted leg retains bounded private
  configuration for callbacks/media/cleanup during DB outage. Tenant service IDs cannot collide in
  live ownership keys. A failed new transfer preserves the original live call.
- [ ] Inject credential-source/key failure separately from the existing admission-store failure
  switch: assert no new dial, source recovery and continued admitted-leg media/callbacks/cleanup.
  Preserve admission-store-only behavior when the required credentials remain available.
- [ ] Document provisioning and the signed local-phone demonstration, including redacted output.
  Keep any live Telnyx audibility check explicitly tagged and separately authorized.

Exit: one complete Telnyx inbound and outbound-transfer call using tenant DB credentials, with
verified webhook ingress and working media/cleanup under the existing carrier contracts.

### Checkpoint 4 — Run the same incoming and transfer flow through Twilio

Depends on checkpoint 3 and the implemented Twilio adapter.

- [ ] Write a failing parity scenario using a tenant Twilio account SID/auth token, its phone
  service binding and the existing provider-neutral phone definition.
- [ ] Add validated Twilio credential provisioning to the common store and service workflow.
  Reject mixed Telnyx/Twilio fields and account/service mismatch before save or activation.
- [ ] Migrate voice webhooks, status callbacks and REST dial/end-call credential resolution.
  Derive exact signature URLs from platform origin plus stored tenant/service route.
- [ ] Migrate `TwilioMedia` authentication too: resolve or use the admitted leg's pinned auth,
  verify WSS signature, then consume the exact single-use token and validate account/call/stream.
- [ ] Add non-consuming, bounded token-to-auth-lease discovery for bound media and pending
  outbound reservations. Verify with the pinned version, then consume against that same lease;
  test wrong signatures, pending binding, expiry, replacement and concurrent-consumption races
  without an unauthenticated waiter, token consumption or fresh DB lookup for an admitted leg.
- [ ] Exercise incoming Voice/TwiML → authenticated media → tenant agent → outgoing private
  briefing → destination press-1 → bridge → cleanup, including duplicate/late callback handling.
- [ ] Test token/signature/account substitution between tenants, revoked/missing bindings, service
  fallback rejection and DB outage after admission. Failed authentication consumes no media token.
- [ ] Repeat durable cross-tenant replay/restart checks for Twilio and independently disable the
  credential source: no new dial, source recovery, existing-leg media/callbacks/cleanup preserved.
  Do not substitute the admission-store-only outage harness for this credential-failure proof.
- [ ] Document the working Twilio provisioning/call flow and retain the original milestone's
  separate pending live-provider audibility gate.

Exit: Twilio delivers the same ordinary call and transfer flow with tenant auth for every
control, callback and media-authentication boundary; no global Twilio credential is consulted.

### Checkpoint 5 — Run the remaining supported providers with their required auth/options

Depends on checkpoints 1–2; execute after the carrier slices in index order.

- [ ] Inventory the installed ReqLLM provider set and existing provider docs/root provider list.
  Deliver provider-specific auth/option handling in small sub-checkpoints; each must provision a
  credential, save a definition, activate its adapter and verify a request with a local double.
- [ ] Cover ordinary API-key providers and existing alternative auth shapes (Bedrock IAM/API key,
  Vertex service account/access token, supported OAuth token input) against installed source.
  Do not promise OAuth onboarding/refresh or accept arbitrary local auth-file paths.
- [ ] Prove nested provider options survive translation and invalid/mutually exclusive auth inputs
  fail before requests. Defaults, protected keys, model validation and supported provider-native
  routing/compaction preserve their existing contracts.
- [ ] Test router model paths, accurate upstream credential ownership and provider usage identity.
  Keep Vxpipe fallback chains and configurable adapter modules absent.
- [ ] Seed conflicting ambient provider/AWS credentials in isolated tests. Requests must use only
  the selected tenant record; Bedrock must never pick up platform S3 credentials.
- [ ] Update each provider page with required tenant auth and inline provider/model examples.
  Preserve optional-option links and their centrally configured ReqLLM documentation version.
  Clearly label unsupported provider/auth combinations until their sub-checkpoint passes.

Exit: every advertised supported provider has a working provisioning-to-request example; optional
settings remain documented without exposing ReqLLM as a public adapter choice.

### Checkpoint 6 — Rotate/revoke tenant credentials while calls are running

Depends on checkpoints 1–5.

- [ ] Write failing operator scenarios for rotate/revoke during an AI call and during admitted
  Telnyx/Twilio legs, including webhook delivery and pending media admission.
- [ ] Deliver trusted rotate/revoke operations with version metadata and bounded audit events.
  New activations use the new version; revoked credentials block new save/publish/prepare/legs.
- [ ] Implement the documented active-configuration lifetime and bounded carrier verification
  overlap. Retain only exact service/leg leases, retire them on teardown, and reject old
  credentials for new incoming calls. Exercise control-plane outage and cleanup after revocation.
- [ ] Verify concurrent credential rotation/revocation and definition writes cannot cross tenant
  scope or persist a revision after an already-observed invalid credential. Record the precise
  commit/activation boundary; no claim of immediate termination of established calls.
- [ ] Demonstrate encryption-key rotation/restart and backup restoration in a disposable DB with
  key versions provisioned externally; missing/wrong keys fail closed with safe diagnostics.
- [ ] Audit errors, Inspect/log output, event projections, archive/plan serialization and
  management summaries for accidental key/token/payload disclosure.

Exit: an operator rotates a tenant credential, sees a new call use it, revokes it and sees a new
call/save rejected, while the existing bounded call/leg behaves as documented.

### Checkpoint 7 — Start and recover the complete platform with environment and DB configuration

Depends on checkpoints 1–6. This is the final operational cutover and acceptance slice.

- [ ] Write a restart/boot scenario with platform env settings, pre-provisioned tenant credentials
  and inline definitions: migrate/start → prepare/join → provider/phone call → permitted artifact
  publication. No runtime config file is available.
- [ ] Remove remaining TOML loader/`VXPIPE_CONFIG`, `vxpipe.toml.sample`, global provider
  credential configuration and unused `apps/vxpipe_config`/TOML dependencies. Update exact child
  dependencies and lockfile entries. Runtime normalization needed by adapters stays with its owner.
- [ ] Audit and delete every superseded provider configuration entry point, reader, merge and
  fallback branch, including `provider_api_key_environment`, global provider model/options and
  application-scope carrier configuration. Remove obsolete settings from docs/examples and
  reject removed public configuration fields; retain no compatibility switch or dormant path.
- [ ] Prove absence of fallback: populate conflicting old provider env/application settings and a
  legacy config file in isolated tests. Without an active tenant DB credential, save/preparation/
  activation must fail with no provider request. With one, only that credential and the definition
  options are used; the old file is never read and SDK ambient discovery is never invoked.
- [ ] Restore and catalog platform database/pool, S3, listener/TLS, callback origin and encryption
  settings in `config/runtime.exs` and `.env.example`. Exercise launcher/Console/Astro wiring;
  no provider secret is required before tenant DB provisioning.
- [ ] Implement the database contract: `VXPIPE_DB_URL` before `DATABASE_URL`, and
  `VXPIPE_DB_POOL_SIZE` before `DB_POOL_SIZE`; default development to `vxpipe_dev` and pool 10
  without database env requirements. Retire `VXPIPE_DATABASE_URL` and update CLI diagnostics,
  setup/provider-operation docs, examples and affected configuration/launcher tests together.
- [ ] Add focused runtime-configuration cases for each alias alone, both with conflicting values,
  unset/blank values, invalid selected URL/pool values, the retired name alone and test-database
  isolation. Demonstrate development boot/provision/prepare using the default local database/pool
  with all four database env vars unset; verify non-development never defaults to `vxpipe_dev`.
- [ ] Convert old profile sources using an explicit operator-supplied registry snapshot, then save
  new immutable revisions through the normal credential gate. Never guess historical aliases or
  rewrite existing revisions; explicitly publish the replacements.
- [ ] Drain/cancel old prepared calls and invalidate their join rights before retiring live old
  plan support. Test rejection of old plans for new activation and retain safe historical
  inspection if required. The generic Erlang term decoder cannot perform this migration.
- [ ] Update architecture, tenant operations, developer/provider docs and the container delivery
  specification. Environment plus tenant DB replaces the proposed deployment JSON/TOML loader;
  JSON call definitions remain. Preserve embedded fixture/local-provider use without Ecto.
- [ ] Obtain the requested independent agent review of the final implementation, fix findings,
  then run all five common root gates once the reviewed checkpoint is ready. Record exact results.
- [ ] Run a disposable PostgreSQL end-to-end acceptance for two tenants plus controlled key/DB
  outage, rotation, restart and profile cutover. Use existing synthetic phone/media lanes;
  distinguish these from externally authorized real carrier audibility checks.
- [ ] Validate source-development/macOS boot now. Verify packaged/container boot only after the
  separate delivery milestone's hold is released; do not claim or require a not-yet-built image.
- [ ] Update the checkpoint evidence ledger, milestone index and labnotes. Leave this milestone
  unchecked for any unresolved acceptance gate; no commits unless requested.

Exit: documented setup and restart produce a working tenant call with env-backed platform storage,
encrypted provider/carrier auth and inline definitions, with all obsolete live configuration
paths removed. Container publishing remains governed by its separate milestone.

## Acceptance matrix

Every case is required; append concrete evidence under its owning checkpoint.

| Flow | Success | Required failure evidence |
| --- | --- | --- |
| Inline provider selection | `google` and `deepgram` select their adapters internally | Profile strings, `req_llm`, adapter fields and invalid option overrides reject |
| Save/publish/prepare | All effective speech/model/phone requirements resolve for the tenant | Missing/revoked/wrong-tenant credential or unknown service creates no new revision/routes |
| Opening and transfers | Independent voice and destination credentials work with default/override rules | Missing later-destination credential blocks save; activation failure preserves source recovery |
| Telnyx | Signed incoming call and outbound accepted phone transfer | Invalid signature/timestamp/connection, application fallback, wrong tenant and duplicate dial reject |
| Twilio | Voice callback, signed WSS media and outbound accepted transfer | Wrong SID/token/URL signature; failed auth consumes no media token or installs a waiter; pending/rotated lease races fail safely |
| Durable isolation | Tenant/canonical service identity scopes persisted duplicate claims | Matching aliases/event/leg IDs in different tenants cannot cross claims, including replay after restart |
| Live isolation | Admitted legs retain exact identity and bounded credentials during DB outage | Credential-source failure is tested separately from admission-only outage; no new dial, tenant cache crossover or speculative redial |
| Rotation/revocation | New calls select current version; active lifetime is explicit | Revoked version cannot admit a new call; key loss/ciphertext swapping fails safely |
| Persistence/inspection | Credentials encrypted; definitions/plans/archives contain safe references | API keys still hash-only; no plaintext/ciphertext payload in call artifacts or logs |
| Platform restart | Database/S3/HTTP/key settings from env; provider auth from tenant DB | No provider env fallback, TOML dependency, old-plan activation or capability-profile lookup |
| Database configuration | Prefixed URL/pool variables win; generic aliases work; development uses `vxpipe_dev` and pool 10 without either pair | Invalid selected values fail safely; retired alias cannot configure persistence; test database/pool are not overridden; no development DB default outside development |
| No alternate provider configuration | Superseded readers/merges/branches are deleted, not disabled | Old env/application/file settings cannot rescue missing DB credentials or override definition options; no SDK ambient lookup or compatibility mode |

## Scope and rejected alternatives

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
- No new management UI is needed for the first slices. The trusted operator interface must be
  sufficient to reproduce each runnable flow; rendered verification applies to UI changes.
- Existing runtime source is not changed by this planning document. Superseded behavior is removed
  by the implementation checkpoints, with migration evidence and no retained live legacy fallback.

## Evidence ledger

Implementation boxes stay unchecked until their runnable exits and failure cases pass.

| Checkpoint | Implementation | Focused/flow evidence |
| --- | --- | --- |
| 1 — Tenant voice call | Not started | Pending |
| 2 — Opening and transfers | Not started | Pending |
| 3 — Telnyx tenant phone flow | Not started | Pending |
| 4 — Twilio tenant phone flow | Not started | Pending |
| 5 — Remaining provider requests | Not started | Pending |
| 6 — Live credential rotation | Not started | Pending |
| 7 — Platform restart and cutover | Not started | Pending |

- [ ] Demonstrate all runnable exits and acceptance cases.
- [ ] Complete the [common implementation gates](index.md#common-implementation-and-verification-gates)
  after independent implementation review.
- [ ] Update this milestone, index and related documentation with actual implementation evidence.

## Specification review

Local source review on 2026-09-15 traced profile selection, provider startup, prepared-plan
encoding, tenant administration, carrier service fallback, webhook/WSS authentication, outbound
leg resolution and sample bootstrap. This review changed the draft from layer-based tasks to
complete call/operator flows and added tenant telephony service lookup before ingress verification.

Agent review by Lorentz on 2026-09-15 identified three missing telephony contracts: durable
tenant-scoped deduplication, non-consuming Twilio auth-lease discovery, and separate credential
versus admission-storage outage tests. Each is now specified in the carrier contracts, owning
checkpoints and acceptance matrix. Bounded re-review reported no remaining blocking findings
or vertical-order contradiction. This is specification review, not runtime implementation approval.
The later explicit-deletion clarification and checkpoint 7 removal/negative-test tasks also
received bounded agent review with no blocking findings; no alternate configuration path is retained.
The database alias/default contract and its checkpoint 7 tasks received bounded agent review
against current runtime/development/test configuration, with no blocking findings or order change.

Documentation checks passed: 131 relative links/anchors across this milestone and the index,
one parsed JSON example, seven sequential checkpoints with exits, 61 unchecked tasks, and index
counts of 26 entries/21 implemented. `git diff --check` passed. No full test suite was run for
this documentation-only change; implementation review and test evidence remain future gates.
