# Destination credential boundaries

## Scope and findings

- Continue checkpoint 2 after the global-reader removal. Independent GPT 6 Astra xhigh source
  review identified missing evidence at the existing destination credential boundaries.
- Existing save validation already traverses effective selections for every participant. These
  contract tests passed against that implementation; no runtime behavior or credential lifecycle
  operation was added and no red failure was manufactured.

## Save validation checkpoint

- Nine PostgreSQL cases cover missing, other-tenant-only and inactive destination model/TTS/STT
  bindings. Entry credentials remain healthy; each failure identifies the destination selection
  and leaves definition/revision/route row counts unchanged. Public errors exclude secret markers.
- A whole-selection fixture override does not require the unused hosted default binding.
  Saved draft data excludes credential payloads.
- Focused Persistence group: 18 tests, 0 failures, 2 excluded, seed 235296. Independent GPT 6
  Astra xhigh review found no blocking issues in these save checks.
- DB activation evidence will follow separately. Checkpoint 2 remains open until the complete
  boundary evidence and umbrella gates pass.

Run from `apps/vxpipe_persistence`:

```shell
mix test test/vxpipe/persistence/inline_tenant_voice_test.exs --seed 235296
```

## Constructor checkpoint

- Named model, voice and listener selections with identical aliases in two tenants resolve only
  the matching tenant payload. Actual ReqLLM/Flux configurations retain complete selection
  overrides instead of merging unused default options.
- New agent and human destination construction rechecks the injected credential source. Updated
  synthetic payloads distinguish fresh construction from copying a previous configuration.
- Missing model/TTS/STT bindings reach the existing preparation failure before client startup;
  retired global speech options cannot rescue them. Plans, inspected destinations and voice-cache
  identity exclude secret markers. No runtime change was needed.
- Focused constructor group: 5 tests, 0 failures. Combined destination/inline-activation/compiler
  group: 15 tests, 0 failures. Final 5-test rerun after replacing keyword-list bracket access also
  passes. All use seed 235296. Independent GPT 6 Astra xhigh review found no blocking issues.

Run from `apps/vxpipe_call_engine`:

```shell
mix test test/vxpipe/call_engine/plan_startup/destination_credentials_test.exs test/vxpipe/call_engine/plan_startup/inline_activation_test.exs test/vxpipe/call_engine/call_definition/inline_capabilities_test.exs --seed 235296
mix test test/vxpipe/call_engine/plan_startup/destination_credentials_test.exs --seed 235296
```
