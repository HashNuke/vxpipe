# Provider integration packages

## Objective

Give each provider one explicit capability manifest and one logical `Vxpipe.Provider.<Provider>`
package while preserving the existing Console, CallEngine and Gateway runtime ownership.

## Decisions

- Use a dependency-light shared provider contract/catalog application and a fixed registry. Do not
  add a registry process, runtime discovery, fallback lookup or compatibility namespace.
- Keep concrete modules in the umbrella child that owns their runtime dependencies, but use the
  common provider namespace. The initial dependency audit showed that Deepgram implements
  CallEngine speech contracts and Telnyx uses Gateway media processes; moving either into a new OTP
  child would create cycles or require an unrelated runtime-contract extraction.
- Provider manifests compose the existing focused credential, STT, TTS and telephony contracts.
  Capability support, scoped configuration and runtime readiness remain separate facts.
- Keep model inference in the shared ReqLLM adapter. Provider packages do not duplicate it.
- Accepted concrete names: `Vxpipe.Provider.Deepgram.STTSocket`,
  `Vxpipe.Provider.Deepgram.TTSSocket`, and
  `Vxpipe.Provider.Telnyx.TelephonyMediaSocket`.

## Baseline

- The previously verified credential test/save separation and tenant-service cleanup were committed
  as `57502189` before this migration.
- Existing Deepgram code is under `Vxpipe.CallEngine.Provider.Deepgram`; existing Telnyx code is
  under `Vxpipe.Gateway.Telephony.Telnyx`; credential-test builders are under
  `Vxpipe.Console.Provider.<Provider>`.
