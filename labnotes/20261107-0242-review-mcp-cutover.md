# Review MCP cutover

- Scope: saved tenant catalog/picker, publication/preparation snapshots, Gateway
  startup wiring, private transport headers and the focused acceptance boundary.
  Production Integrations UI and separate-node acceptance remain later checkpoints.
- Independent review found the picker advertised schemas that compilation cannot
  execute. A valid/unsupported sibling regression failed before filtering unsupported
  choices; valid/native choices remain available. Outage coverage seeds an actual
  application catalog to prove it is not used as fallback.
- Added PostgreSQL saved-record publication/preparation and real loopback MCP
  execution through Gateway's startup-options boundary. It reproduced a local
  rejection being classified as unknown. Exact asynchronous and pinned synchronous
  transport forms now classify it as not submitted; other errors stay ambiguous.
- Reproduced a saved bearer token in raw supervisor reports. Default Logger
  translation suppresses SASL reports, so handler-only capture missed the exposure;
  a primary-filter capture before translation proves the report exists and checks
  its raw term. The managed snapshot now contains no token, extra header or keyring.
  Complete validated headers are resolved immediately before submission instead.
- Rejected a reusable config vault because its retention/transfer lifetime would
  add complexity. The runtime descriptor uses the configured source, with explicit
  nonsecret resolver references for operation-level overrides. Endpoint/source
  binding and Basic/Bearer scheme regressions failed before their guards were added.
- OAuth projection retains the final persisted MCP headers with the current token,
  excluding refresh and client secrets. HTTP replaces the full header set rather
  than merging stale values. Client and SSE status reports are redacted.
- Added an exact checksum-pinned upgrade from the previous two-file dependency
  patch. The old preparation script rejected this legitimate state in a red test.
  The upgrade test derives its declared preimage without requiring repository
  history, allowing shallow CI clones. All seven preparation tests pass.
- Design review clarified the embedding boundary: explicit catalogs remain usable
  through direct CallEngine startup; packaged Gateway requires saved tenant records.
  Legacy static embedding arguments are outside this managed-runtime privacy claim.
- Current evidence: 317 Calls tests, 179 MCP tests including integration fixtures,
  870 Gateway tests (13 excluded), 37 focused CallEngine tests and three tagged
  PostgreSQL/wire cases pass, including raw activation/client failure reports.
  Seven patch and 33 setup tests pass. Root format, warnings-as-errors compile,
  strict Credo and unused-dependency checks pass. Full umbrella acceptance remains
  a final milestone gate.
- Independent adversarial review of the exact 42-file index found no remaining
  source or staging blockers. Its documentation notes were incorporated. Full
  per-admission room/transfer and independent-node acceptance remain pending.
