# Provider integration packages

## Objective

Give each provider one explicit capability manifest and one logical `Vxpipe.Providers.<Provider>`
package while preserving the existing Console, CallEngine and Gateway runtime ownership.

## Decisions

- Use a dependency-light shared `vxpipe_providers` contract/catalog application and a fixed registry. Do not
  add a registry process, runtime discovery, fallback lookup or compatibility namespace.
- Keep concrete modules in the umbrella child that owns their runtime dependencies, but use the
  common provider namespace. The initial dependency audit showed that Deepgram implements
  CallEngine speech contracts and Telnyx uses Gateway media processes; moving either into a new OTP
  child would create cycles or require an unrelated runtime-contract extraction.
- Provider manifests compose the existing focused credential, STT, TTS and telephony contracts.
  Capability support, scoped configuration and runtime readiness remain separate facts.
- Keep model inference in the shared ReqLLM adapter. Provider packages do not duplicate it.
- Accepted concrete names: `Vxpipe.Providers.Deepgram.STTSocket`,
  `Vxpipe.Providers.Deepgram.TTSSocket`, and
  `Vxpipe.Providers.Telnyx.TelephonyMediaSocket`.

## Baseline

- The previously verified credential test/save separation and tenant-service cleanup were committed
  as `57502189` before this migration.
- Existing Deepgram code is under `Vxpipe.CallEngine.Provider.Deepgram`; existing Telnyx code is
  under `Vxpipe.Gateway.Telephony.Telnyx`; credential-test builders are under
  `Vxpipe.Console.Provider.<Provider>`.

## Deepgram provider checkpoint

- Registry and credential tests first failed on missing contract/schema modules (3 and 2 tests).
  The new `vxpipe_providers` child has no runtime process or dependency on Console, CallEngine or
  Gateway. Its current fixed manifest declares Deepgram only; other providers remain on their
  existing paths until their complete per-provider migrations.
- Deepgram now owns its credential schema and pure test-request description in `vxpipe_providers`.
  Its STT/TTS implementation modules, including `STTSocket` and `TTSSocket`, live in CallEngine under
  the `Vxpipe.Providers.Deepgram` namespace. Provider-specific option validation lives beside those
  sessions. Calls and Console resolve the declared credential capabilities; CallEngine resolves
  STT/TTS adapters through the manifest. No runtime supervision or call logic changed.
- Green evidence: provider tests 6, CallEngine complete 846 (14 excluded), local speech socket
  integration 13, Calls complete 117, Console complete 186 (one excluded); all zero failures.
  Root format, warnings-as-errors compile, strict Credo and unused dependency checks pass.
  Old Deepgram module names are absent from source and tests. In a provider-only test environment,
  `Registry.resolve_capability("deepgram", :stt)` returns
  `{:error, :provider_implementation_unavailable}` rather than calling an absent module.

## Telnyx provider checkpoint

- Telnyx contract and manifest tests first failed on absent schema/probe and registry entries (four
  failures). Its credential schema preserves the bounded API key and optional 32-byte verification
  key; the probe preserves the existing read-only call-control-application request.
- Provider-specific Gateway modules, including HTTP webhook/media handlers, now live under
  `Vxpipe.Providers.Telnyx`. `TelephonyMediaSocket` replaces the generic Telnyx `MediaSocket` name.
  Gateway resolves the telephony service profile through the manifest; Calls, Persistence and
  Console use the provider-owned credential shape and probe. The fixed registry grows only after the
  complete provider is migrated.
- The first focused carrier run found stale socket names in fixture/harness code and an accidentally
  qualified public-key reference in Persistence. Both were corrected; the 72-test focused gateway
  set passed after the correction, and a 31-test HTTP/carrier set passed after moving HTTP handlers.
  The Telnyx provider contract suite passes 6/6 and the Calls credential test passes 1/1.
- Full child acceptance: Gateway 477 tests, zero failures (seven excluded); Calls 117, Console
  186 (one excluded), Persistence 184 (12 excluded), all zero failures. Root format,
  warnings-as-errors compile, strict Credo and unused-dependency checks pass. The final umbrella
  suite remains the milestone's final checkpoint.
