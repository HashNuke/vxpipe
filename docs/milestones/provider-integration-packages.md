# Provider integration packages

Status: Deepgram and Telnyx integrations migrated and tested; the shared registry declares both.
Implementation is **2 of 7 provider/final checkpoints complete**. Each provider is migrated, tested,
fixed and committed as a complete unit before the next provider is added to the registry.

Prerequisites: [Simpler speech integrations](simpler-speech-integrations.md),
[Telnyx calls](telnyx-calls.md), and
[Tenant-scoped provider credentials](tenant-provider-credentials-and-platform-configuration.md).

Design sources: [provider integration packages](../provider-integration-packages.md),
[speech provider contract](../speech-provider-contract.md),
[provider credential testing](../provider-credential-validation.md), and
[gateway/console boundary](../gateway-console-boundary.md).

## Runnable outcome

Console, CallEngine and Gateway resolve provider capabilities through one fixed manifest registry.
Deepgram speech uses `Vxpipe.Providers.Deepgram`, including `STTSocket` and `TTSSocket`. Telnyx
telephony uses `Vxpipe.Providers.Telnyx`, including `TelephonyMediaSocket`. Credential schemas and
test-request construction belong to their provider namespaces. Missing capabilities fail explicitly;
there is no compatibility namespace, fallback adapter or dynamic registration path.

The migration changes code organization and discovery only. Existing call supervision, participant
ownership, room policy, barge-in, cancellation identifiers, readiness, media formats, telephony
admission and credential storage remain behaviorally unchanged.

## Design review

- [x] The manifest composes focused capability contracts instead of defining one large provider
  behaviour with optional callbacks.
- [x] Capability support, scoped configuration and runtime readiness remain distinct states.
- [x] ReqLLM remains the generic model-inference runtime and is not copied into provider packages.
- [x] A dependency audit rejected per-provider OTP applications for this migration because the
  concrete integrations implement contracts owned by CallEngine and Gateway. Logical provider
  namespaces preserve those dependency directions without adding processes.
- [x] The registry is fixed and has no legacy or fallback lookup.
- [x] Provider-by-provider migration keeps the shared registry incremental: each commit includes a
  provider's complete declared capabilities, credential schema/test, consumers and focused evidence.

## Checkpoint A — Deepgram and shared contract

- [x] Add dependency-light `vxpipe_providers`, the capability contract and a fixed registry with
  exact unsupported-provider/capability and unavailable-implementation results.
- [x] Move Deepgram credential schema and bounded test-request construction into its manifest;
  resolve these through the registry from Calls and Console.
- [x] Move Deepgram modules and tests to the `Vxpipe.Providers.Deepgram` namespace.
- [x] Rename the concrete wire modules to `STTSocket` and `TTSSocket`; retain their shared private
  connection machinery and existing semantic session contracts.
- [x] Replace CallEngine's Deepgram provider-name/module lists with manifest lookup while keeping
  provider-specific option validation inside the Deepgram package.
- [x] Exit: native Deepgram STT/TTS focused suites, shared speech conformance and affected room tests
  pass with no old Deepgram module loaded.

Deepgram evidence: the contract tests failed before the registry/schema existed (3 registry and 2
credential tests). The provider tests now pass 6/6; CallEngine's full 846-test suite passes with
zero failures (14 excluded). The controlled local speech-socket integration lane passes 13/13;
Calls and Console complete suites pass 117/117 and 186/186 (one excluded in Console). The root
format, warnings-as-errors compilation, strict Credo and unused-dependency checks pass. A
provider-only test environment resolves Deepgram STT as `provider_implementation_unavailable`.
The Deepgram module-namespace search finds no old references in source or tests. The final umbrella
suite and broader consumers remain part of checkpoint G.

## Checkpoint B — Telnyx package

- [x] Move Telnyx-specific modules and tests to `Vxpipe.Providers.Telnyx`.
- [x] Rename `MediaSocket` to `TelephonyMediaSocket` and update HTTP/media/telephony composition.
- [x] Move Telnyx credential schema/test into its manifest and migrate Calls/Console consumers.
- [x] Resolve Telnyx telephony support through its manifest without changing signed webhook,
  admission, media, transfer, cancellation or cleanup behavior.
- [x] Exit: Telnyx unit, HTTP, media, carrier-harness and affected transfer tests pass with no old
  Telnyx module loaded.

Telnyx evidence: the new contract tests first failed on absent credential/probe and manifest
entries (four failures). Provider contract tests pass 6/6; Gateway's full default suite passes
477/477 (seven excluded), including signed webhook, media, carrier-harness and transfer cases.
Calls, Console and Persistence full child suites pass 117/117, 186/186 (one excluded) and 184/184
(12 excluded). Root format, warnings-as-errors compilation, strict Credo and unused-dependency
checks pass. The old Telnyx production namespaces and socket name are absent from source; the
final root umbrella suite remains in checkpoint G.

## Checkpoint C — Google AI Studio package

- [ ] Add its credential schema and optional credential-test request to the fixed manifest; route
  Calls and Console through it without moving shared ReqLLM inference.
- [ ] Exit: credential shape, test/save and explicit absence of speech/telephony capabilities pass.

## Checkpoint D — Rime package

- [ ] Add the provider-owned credential schema and credential-test request to its manifest; migrate
  Calls and Console consumers without inventing an unsupported runtime capability.
- [ ] Exit: credential shape, test/save and unsupported-capability tests pass.

## Checkpoint E — Twilio package

- [ ] Move provider-specific telephony modules and tests to `Vxpipe.Providers.Twilio`, with the
  credential schema/test and actual telephony capability in its manifest.
- [ ] Migrate Gateway, Calls and Console consumers while preserving webhook, media and call behavior.
- [ ] Exit: carrier, HTTP/media and affected transfer suites pass with no old module loaded.

## Checkpoint F — Zenmux package

- [ ] Add the credential schema/test to its manifest and migrate Calls/Console; leave model inference
  in shared ReqLLM.
- [ ] Exit: credential shape, test/save and unsupported-capability tests pass.

## Checkpoint G — Final consumers and acceptance

- [ ] Remove duplicated backend provider capability lists and update provider authoring/credential
  documentation with the manifest workflow.
- [ ] Prove manifests report every migrated provider's actual capabilities and explicitly deny absent
  capabilities; preserve bounded credential probes and independent Save.
- [ ] Search compiled source and tests for obsolete provider namespaces; do not retain aliases,
  wrappers or fallback modules.
- [ ] Run the relevant frontend checks, rendered Console inspection if catalog output changes, all
  five root gates and bounded existing speech/telephony regression lanes.
- [ ] Exit: implementation is 7 of 7 complete, the index is synchronized, and each provider is
  committed as a usable vertical slice.
