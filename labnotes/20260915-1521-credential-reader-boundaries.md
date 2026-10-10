# Credential reader boundaries

> Relocated from `docs/credential-reader-boundaries.md` on 2026-10-09. First recorded source commit: `1ccc822a54c1` (2026-09-15T22:21:37+07:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260915-2203-audit-credential-readers](20260915-2203-audit-credential-readers.md).
> Maintained contracts/progress: [provider-credential-storage](../docs/provider-credential-storage.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

## Decision

The call plan pins provider, model, options and credential binding name. Each new preparation
resolves that binding through the host-injected tenant credential source. An initialized client
keeps its configuration for its owned lifetime. Starting a separate client for private briefing
or replacing a lost speech client requires a fresh lookup, even when the voice selection is the
same as the source agent's.

Source speech resolution uses the plan's source participant selection and the current request's
activation ID. The latter matters when an agent has returned to the call with a new activation.
The lookup runs inside the existing bounded preparation/restoration worker. Missing credentials
follow existing preparation failure handling before a new speech transport or phone dial starts.
When the source speech client is still present, recovery reuses it and performs no new lookup.

This changes credential acquisition only. Existing transfer, media, readiness and recovery
protocols retain their ownership and deadlines. It implements the
[credential milestone](milestones/tenant-provider-credentials-and-platform-configuration.md)
under the [approved scope correction](milestones/credential-cutover-scope.md).

## Reader inventory

| Construction boundary | Credential path | Evidence/status |
| --- | --- | --- |
| Initial agent model | `PlanStartup.new` → `AgentActivation` → `AgentModel` → `CredentialSource` | Initial inline activation and persisted tenant voice checks. |
| Later agent activation | `DestinationPreparer` → `PlanStartup.agent_destination` → the same model/speech resolvers | Named tenant isolation, whole-selection overrides and fresh construction checks; persisted activation verifies the current DB payload reaches the Google request. |
| Initial and destination TTS | `PlanStartup` → `resolve_provider` → `CredentialSource` | Initial inline activation and fresh destination construction checks; persisted activation verifies current Deepgram authentication. Source briefing/restoration corrections below. |
| Independent opening TTS | `PlanStartup.opening_runtime` → `resolve_provider` | Four persisted opening cases, tenant/binding cache separation and unavailable-binding rejection. |
| Connection STT | `ConnectionSpeechPreparation` → `PlanStartup.connection_speech_to_text` | Fresh source, bounded worker cancellation and persisted credential recheck tests. |
| Private destination STT | `PlanStartup.human_destination` → `resolve_provider` | Named tenant isolation, independent listener options and fresh construction checks; unavailable bindings fail before client startup. |
| Private briefing TTS | `HumanDestinationPreparer` → transfer `Runtime.source_text_to_speech` → `PlanStartup.participant_text_to_speech` | Fresh named source binding before new transport/dial; missing binding preserves the existing source client. |
| Source TTS replacement | `RoomTransferSupervisor.recover` → transfer `Runtime.source_text_to_speech` | Fresh lookup within the existing 750 ms budget; unavailable binding starts no transport and enters existing terminal failure handling. |
| Hosted persistence bridge | Calls `ProviderCredentialSource` → `CallSpecCredentials` → encrypted repository | Tenant/provider/name/status/auth validation; persistence tests verify DB reads and safe errors. |
| New incoming carrier leg | Stored ingress → `TelephonyServices.resolve` → private `ConfiguredService` → verification and activation | Telnyx/Twilio encrypted DB-to-HTTP and two-tenant signature checks. |
| New outbound carrier leg | Pinned `ServiceReference` → `ServiceRegistry.fetch_for_tenant` → existing connector/adapter | Exact tenant REST auth, missing/revoked source and deadline checks. |
| Existing carrier callbacks/media/cleanup | Initialized leg/admission configuration | Storage-outage callbacks, retained Twilio WSS auth and exact-owner retirement checks. |
| Raw embedded `CreateRoom` | Empty rooms and deterministic text only | Retired global model selector and automatic TTS/STT construction removed. Hosted capabilities use inline plans; fixture/Morse selections remain credential-free. |

## Raw-room cutover

`CreateRoom` admits empty rooms and the credential-free deterministic text agent. Its retired
`:model_inference` selector is rejected; a stale manually constructed command fails room startup.
Raw-room startup and attachment no longer construct speech clients from application settings.
Model and speech calls compile an inline call spec and use `start_call`, including embedded
fixture/Morse calls. Application settings still register adapters, transports and resource limits;
inline selections and the tenant credential source supply provider request configuration.

The turn and WebRTC tests now use that same inline boundary. Their history, streaming, queueing,
interruption and playout assertions remain in place. The live Deepgram lane explicitly binds its
supplied test key to its test tenant through a credential source; it requires separate live execution.

## Rejected alternatives and remaining work

- Retaining an opt-in global credential fallback would preserve the bypass. A replacement
  global local-provider option scheme is unnecessary because inline fixture/Morse calls already
  support credential-free embedding.
- Copying the source client's decrypted configuration into a new client skips current tenant
  credential validation. Keep its non-secret selection and resolve the selected binding again.
- Reusing a live client during failure handling is valid. Adding database reads to media frames,
  speech chunks or each use of an already prepared configuration is unnecessary.
- Database calls in Room Authority would block control processing. Keep lookup in the existing
  worker and retain its existing cancellation/deadline contract.
- No upstream key rotation, verification overlap, refresh schedule or new call-flow feature is
  introduced. Synthetic credential changes in tests distinguish a fresh lookup from a copied
  configuration; they do not prescribe a provider credential lifecycle.

Destination boundary coverage now includes missing, other-tenant-only and inactive model/TTS/STT
bindings before call spec writes, plus named destination isolation and whole-selection overrides.
Carrier readers and the existing Zenmux adapter are also migrated. The milestone ledger records
checkpoint completion and umbrella gate results; final platform configuration remains separate.

## Verification

The briefing regressions first failed because no second lookup occurred and the new transport
received the cached key. The restoration regression first failed because the replacement transport
also received that cached key. Four focused cases now cover fresh available credentials and missing
credentials for both paths. The changed code has no secret-bearing public fields or new storage.
Full regression and independent review evidence is recorded in the
[reader labnotes](20260915-2203-audit-credential-readers.md).

Raw-room rejection and conflicting global speech settings are covered by focused regressions.
Migration and final gate evidence is recorded in the
[global-reader labnotes](20260915-2223-remove-global-readers.md).

Destination save and constructor checks passed against the existing implementation. A tagged
database-backed activation test changes only synthetic encrypted payloads after entry preparation
and observes the current values at the Google/Deepgram adapter boundaries. Inactive bindings
instead produce existing safe failure/history, start no destination provider request, and leave
the source able to respond. Plans, cache identity and public projections exclude secret payloads.
Focused results and independent review are recorded in the
[destination labnotes](20260915-2250-destination-credential-boundaries.md).

Carrier ownership, removed static options and exact public-origin behavior are documented in
[tenant telephony services](../docs/tenant-telephony-services.md#live-readers-and-platform-callback-origin).
