# Telnyx credential provisioning

## Checkpoint

- Start the Telnyx DB-reader cutover with an existing trusted operator flow: provision an
  encrypted named API key and resolve it for its exact tenant/provider/name. Telnyx is already a
  supported carrier; this adds no new provider, auth mode, key-rotation operation or call behavior.
- Reuse `ProviderCredentials`, the encrypted store and protected-input CLI. Add Telnyx to the
  closed credential validator with the carrier configuration's existing 4,096-byte key limit.
  Preserve the Google/Deepgram 8,192-byte limit, printable non-whitespace input and payload-only
  API-key shape. Connection ID and verification public key belong to the forthcoming service binding.
- Service registration and live carrier readers remain pending. Provisioning alone does not
  complete checkpoint 3 or change current gateway service resolution.
- Updated provisioning docs also remove stale checkpoint-1 status and the superseded claim that
  third-party revocation/backup drills belong to checkpoint 6.

## Red-green evidence

- Added a two-tenant named Telnyx encrypted-store test and a protected-input operator command test.
  The focused group first reported 14 tests, 2 failures, both `invalid_provider_auth` for Telnyx.
- Expanded malformed-auth coverage to reject Telnyx control/whitespace input, keys over 4,096
  bytes, mixed auth/service metadata and unsupported auth kinds; unsupported Bedrock stays rejected.
- After the validator change the focused group passes: 14 tests, 0 failures, seed 235296.
- Root format, warnings-as-errors compile and strict Credo pass. The owning-app regressions pass:
  Calls 81 tests, 0 failures; Persistence 89 tests, 0 failures, 6 excluded, seed 235296.
- Independent GPT 6 Astra xhigh review found no code, ownership or privacy blocker. Corrected
  a documentation sentence that implied the pending Telnyx live readers already used the store.
- All 154 local links in the affected documentation resolve; milestone and index consistently
  record 2 complete, 2 partial and 3 not started, with checkpoint 3 still open.
- Commit this reviewed provisioning chunk before adding service bindings. Full umbrella tests
  and the unused-dependency gate remain pending for the ongoing checkpoint; no complete Telnyx
  reader acceptance is claimed.

Run from `apps/vxpipe_persistence`:

```shell
mix test test/vxpipe/persistence/provider_credential_store_test.exs test/vxpipe/persistence/provider_credential_tasks_test.exs --seed 235296
```

## Full regression result

- After committing provisioning as `9c54f39`, completed the remaining root suite and unused-lock
  gate. All five root gates pass: 1,534 tests, 0 failures, 33 excluded, seed 235296, module
  preloading, one test-file compilation at a time and concurrency four.
- App totals: MCP 37, Agent Runtime 93, Engine 695, Calls 81, Gateway 413, Artifacts 20,
  Persistence 89 and Console 106. Logs: `tmp/telnyx-provision-root-test.log` and
  `tmp/telnyx-provision-root-unused.log`; earlier static-gate logs retain the same prefix
  without `root-`. No runtime source changed during this run.
- The separately committed provider inventory changes documentation only. Telnyx service
  registration and live-reader migration remain pending; checkpoint 3 is still partial.
