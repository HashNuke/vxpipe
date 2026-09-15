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
- Constructor and DB activation evidence will follow in separate commits. Checkpoint 2 remains
  open until the complete boundary evidence and umbrella gates pass.

Run from `apps/vxpipe_persistence`:

```shell
mix test test/vxpipe/persistence/inline_tenant_voice_test.exs --seed 235296
```
