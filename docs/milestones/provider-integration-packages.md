# Provider integration packages

Status: specification reviewed; implementation is **0 of 5 checkpoints complete**.

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

## Checkpoint A — Contract and fixed catalog

- [ ] Add the dependency-light `vxpipe_providers` umbrella child with the `Vxpipe.Providers`
  contract, capability types and `Vxpipe.Providers.Registry`.
- [ ] Add manifests for every currently configurable provider and focused tests for exact supported,
  unsupported-provider and unsupported-capability results.
- [ ] Make provider/auth validation resolve provider-owned credential schemas through the registry.
- [ ] Exit: Calls and provider-contract focused suites pass, with no provider list remaining in
  `Vxpipe.Calls.ProviderAuth`.

## Checkpoint B — Provider-owned credential testing

- [ ] Move credential-test contracts and request builders to `Vxpipe.Providers.<Provider>`.
- [ ] Make the Console HTTP executor resolve the declared credential-test capability rather than its
  own provider map.
- [ ] Preserve one bounded request, disabled retries/redirects, secret filtering and independent Save.
- [ ] Exit: all provider request-shape and test/save endpoint tests pass; unsupported lookup performs
  no network request.

## Checkpoint C — Deepgram package

- [ ] Move Deepgram modules and tests to the `Vxpipe.Providers.Deepgram` namespace.
- [ ] Rename the concrete wire modules to `STTSocket` and `TTSSocket`; retain their shared private
  connection machinery and existing semantic session contracts.
- [ ] Replace CallEngine's Deepgram provider-name/module lists with manifest lookup while keeping
  provider-specific option validation inside the Deepgram package.
- [ ] Exit: native Deepgram STT/TTS focused suites, shared speech conformance and affected room tests
  pass with no old Deepgram module loaded.

## Checkpoint D — Telnyx package

- [ ] Move Telnyx-specific modules and tests to `Vxpipe.Providers.Telnyx`.
- [ ] Rename `MediaSocket` to `TelephonyMediaSocket` and update HTTP/media/telephony composition.
- [ ] Resolve Telnyx telephony support through its manifest without changing signed webhook,
  admission, media, transfer, cancellation or cleanup behavior.
- [ ] Exit: Telnyx unit, HTTP, media, carrier-harness and affected transfer tests pass with no old
  Telnyx module loaded.

## Checkpoint E — Consumers, documentation and final acceptance

- [ ] Remove duplicated backend provider capability lists and update provider authoring/credential
  documentation with the manifest workflow.
- [ ] Prove manifests report the actual Deepgram, Google and Telnyx capabilities and explicitly deny
  absent capabilities.
- [ ] Search compiled source and tests for obsolete provider namespaces; do not retain aliases,
  wrappers or fallback modules.
- [ ] Run the relevant frontend checks, rendered Console inspection if catalog output changes, all
  five root gates and bounded existing speech/telephony regression lanes.
- [ ] Exit: implementation is 5 of 5 complete, the index is synchronized, and each checkpoint is
  committed as a usable vertical slice.
