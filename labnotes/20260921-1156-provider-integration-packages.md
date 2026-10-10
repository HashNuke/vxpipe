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

## Google AI Studio provider checkpoint

- The contract tests failed on missing schema/probe modules and registry entry (four failures),
  then passed 6/6. Google owns its bounded API-key shape and read-only model-list probe in
  `vxpipe_providers`; Calls and Console resolve these through the manifest. The shared ReqLLM model
  runtime remains in AgentRuntime, and the manifest declares no STT, TTS or telephony capability.
- Calls operator credential tests pass 18/18. Complete Calls and Console suites pass 117/117 and
  186/186 (one excluded). No network interoperability probe was run; the default lane uses a
  synthetic request adapter.

## Rime provider checkpoint

- The new contract tests failed on absent modules and manifest entry (four failures). Rime now
  owns its bounded credential shape and existing one-request `POST /oov` probe in
  `vxpipe_providers`; Calls and Console resolve them through the manifest. The Rime manifest does
  not declare a speech capability without a concrete speech runtime.
- Provider suite passes 12/12; complete Calls and Console suites pass 117/117 and 186/186
  (one excluded), all zero failures.

## Twilio provider checkpoint

- Contract tests failed on missing schema/probe and manifest (four failures), then passed 6/6.
  Twilio now owns account/stream/call identifier checks, credential schema/probe, HTTP webhook and
  media handlers, telephony adapter, pipelines, and `TelephonyMediaSocket` in its provider namespace.
  The pure identifier and credential modules compile in `vxpipe_providers`; concrete telephony
  modules continue to compile in Gateway. Calls, Console and Gateway resolve the declared
  capabilities without a compatibility path.
- Focused provider/HTTP/carrier tests pass 68/68. The broader Gateway telephony suite passes
  108/108; full Calls and Console suites pass 117/117 and 186/186 (one excluded). All zero failures.
  The default lane does not contact Twilio's external API.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency checks pass.
  A test-build module-loader check confirms old Twilio media/HTTP, Telnyx socket and Deepgram
  speech module identities are unavailable after compilation.

## Zenmux provider checkpoint

- Contract tests failed on missing modules and manifest entry (four failures). Zenmux now owns its
  bounded API-key shape and read-only model-list probe in `vxpipe_providers`. Calls and Console use
  the registry for all six provider credential schemas and tests; the old Console provider map and
  probe behaviour are removed. Zenmux inference remains in shared ReqLLM.
- Provider suite passes 16/16; complete Calls and Console suites pass 117/117 and 186/186 (one
  excluded), all zero failures.

## Final consumer review

- Added `Credential.auth_kind/0` after a failing registry contract test (one failure). Console
  credential input and Calls credential metadata now derive the auth kind from the provider schema;
  the six-provider credential list is no longer duplicated in those consumers. Provider tests pass
  17/17, Calls operator tests 18/18 and the full Console child suite 186/186 (one excluded).
- Rendered the local operator service connection dialog in Chrome at desktop and 390-pixel mobile
  widths. Google displayed separate Test credentials and Save actions, and the form remained usable.
  The static frontend badges describe future provider offerings rather than currently installed
  runtime capabilities; the separate `labnotes/issues/setup-catalog-runtime-capabilities.md` records
  that pre-existing difference. No credential was submitted in the browser pass.
- Final acceptance: the root default suite passes 1,979 tests, zero failures and 42 excluded. The
  controlled local speech-socket integration lane passes 13/13. Root format, warnings-as-errors
  compile, strict Credo and unused-dependency checks pass. Console asset type check, lint and all
  185 tests pass. Source and compiled-module checks find no obsolete provider namespaces.
