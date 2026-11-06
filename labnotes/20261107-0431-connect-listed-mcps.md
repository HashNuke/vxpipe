# Connect listed MCPs

## Checkpoint scope and decisions

- Inspected the existing Console directory client/cache/facade and the hosted
  directory implementation. The hosted API has list/category routes only. Reuse
  the exact originating public page request to resolve an entry; do not add a
  second directory API or scan all pages. Native Services credential APIs remain
  unchanged.
- A bounded lookup reference carries directory ID, entry ID/revision and normalized
  page parameters. The backend validates the fetched page and returns a whitelist
  of accepted public configuration. Fresh-cache semantics remain unchanged; no
  stale response fallback on failure.
- Extend the existing tenant discovery operation, with authorization before lookup,
  the existing preflight deadline/admission boundary, identity checks on its result
  and authority refresh before returning. This remains non-mutating discovery.
- Saved template configuration, OAuth attempt binding, listed connection forms and
  duplicate/reconnect lifecycle are still pending T6a/T6b work. The future mutation
  must resolve the reference again rather than trust a browser-returned snapshot.

## Red/green evidence

- Resolver: eight tests initially failed because the module did not exist; all
  eight passed after implementation (seed 871620).
- Calls boundary: new listed proposal test initially returned
  `invalid_mcp_preflight`; all 16 connection tests passed after implementation
  (seed 487580).
- Console adapter: two tests initially rejected listed input; focused discovery,
  endpoint and resolver tests then passed (18 tests).
- HTTP contract: changed entry initially returned generic
  `mcp_connection_unavailable`; now returns the fixed `mcp_listing_unavailable`
  error so the caller can ask for a fresh directory selection.
- Logging regression: a rejected nested `private_key` field initially appeared
  in Phoenix request logs. Added a whole-reference filter; the regression passed
  in the 67-test focused suite (seed 2953).
- Inventory reference regression initially failed because the joined row lacked
  its lookup reference; the same focused suite passed after adding it.
- Format, warnings-as-errors compilation, strict Credo and unused dependencies
  passed. A formatting command initially ran with root-relative paths from the
  child directory; rerunning from the root corrected the invocation.
- Changed documentation links and heading anchors pass validation.

## Adversarial review corrections

- First independent source review found no code/security blocker. Corrected its
  documentation finding: invalid outer proposals use `invalid_mcp_preflight`;
  invalid references reaching the resolver use `invalid_mcp_listing`.
- Added the requested lifecycle evidence using the real directory cache. Caller
  cancellation and preflight expiry terminate the discovery continuation while
  an independent public fetch is held. After releasing that fetch, its result is
  cached but no MCP DNS/anonymous request begins. All four adapter tests pass
  (seed 529271). These corrections are tracked separately in T6a.

## Final checkpoint verification

- Root umbrella: **4,901 tests, zero failures, 201 excluded**, seed 177411, exit 0.
  The Console group includes all four listed-preflight tests added for review
  (509 Console tests total). No external provider interoperability is claimed.
- Root format, warnings-as-errors compile, strict Credo and unused dependency
  checks pass. Format/Credo were repeated after the review test additions.
- Independent adversarial re-review and exact-index review are clean across all
  15 staged paths. No unintended work or remaining scoped findings.
- No frontend component changed; no new rendered-browser claim. Lean does not
  apply to this discovery checkpoint because speech/source-cutover state machines
  are unchanged. The milestone/index remain incomplete for the remaining slices.
