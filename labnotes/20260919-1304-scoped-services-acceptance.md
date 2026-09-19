# Final scoped-service acceptance

D2 combines the already reviewed scoped authorization, credentials and ingress
boundaries with C3b's application/number configuration. It adds acceptance evidence,
not a new credential policy or live-provider claim.

- On an owned disposable PostgreSQL database, the Console saved platform Telnyx
  credentials, created and edited an inherited tenant application, and replaced
  another tenant's API-only override with a complete API/public-key payload.
  The API-only override could not borrow the platform public-key flag. A duplicate
  application ID failed without losing input; correcting it succeeded.
- The first route-publication fixture omitted Google's explicit credential name.
  It failed closed and removed its owned database. The corrected fresh fixture
  seeded applications through the public Calls APIs and published two tenant call
  specs using their explicit Google binding. The Console then showed both current
  published numbers, revisions and caller participants under the correct tenant.
- Restart retained application IDs, edited application metadata and number routes.
  Re-encryption followed by restart with only the new key retained credential IDs,
  owners and decrypted payload digests as well. Fresh browser navigation proved
  both tenants' directories still rendered with their respective credential source.
- The owned browser session, Console server, disposable database and browser auth
  state were removed. Synthetic provider validation does not establish upstream
  key validity, public webhook reachability or a successful live Telnyx call.
- C3b1's first umbrella run had one native WebRTC handoff timeout. Five isolated
  runs and the final full umbrella run passed unchanged; no cause or runtime fix
  is inferred. The passing combined run closes the acceptance gate.

- Disposable schema acceptance passes: upgrade, rollback and re-upgrade preserve
  legacy application/credential IDs and the ciphertext digest. A new scoped binding
  resolves from a fresh VM. Rollback rejects live scoped bindings atomically, and
  the next fresh VM still resolves the same application and platform verifier.
  The exercise removes its owned database on completion.
- Root format, compile with warnings as errors, strict Credo and unused-dependency
  checks pass. `mix assets.build` passes; frontend verification is recorded in C3b2.

- Final root test run, `mix test --seed 772211 --max-cases 1`: 1,798 tests,
  zero failures, 40 excluded. By owner: MCP 37, Agent Runtime 95, Call Engine 700,
  Calls 117, Gateway 460, Artifacts 20, Persistence 184, Console 185. No other
  native-media test command ran concurrently.
- C3b1 is committed as `1193023`; C3b2 as `19c8a4e`. The final documentation
  checkpoint synchronizes the plan, scoped binding decision and milestone index.
  All 13 implementation slices are accepted; broader demo/bootstrap work retains
  its separate unchecked gates. Relative documentation links and diff checks pass.
