# Pin tenant phone services

## Scope and planned boundary

- Continue checkpoint 3 from clean `1bfbf95`. Checkpoint 6 is complete; the shared umbrella
  gate retains the previously reproduced native Morse-audio failure. Credential work can progress.
- Pin only non-secret tenant/service/provider/account/credential identities in hosted prepared
  plans. Resolve each distinct tenant-local alias once per compile and reuse that snapshot for
  participants sharing an alias. Include the resulting metadata in the existing plan digest.
- Reuse the active-service transaction for the final web-preparation write, comparing the actual
  prepared references under its locks. Validate every participant before deduplicating aliases.
  Do not pin secret payloads, credential versions or platform encryption-key IDs.
- Keep the public connection JSON unchanged. Engine owns only neutral reference data; Calls owns
  host lookup/projection; Persistence owns locked comparison. Raw embedded Engine compilation
  remains independent of Calls/Ecto. Older serialized plans remain inspectable without repinning.
- This is a partial prerequisite for the carrier reader cutover. Incoming final insertion,
  live-leg reference enforcement and rejection of old hosted plans remain pending. No claim that
  pinning alone secures activation, and no new provider/authentication mode is introduced.
- Add focused red tests for compiled identity/privacy/deduplication, final-write binding changes,
  mismatched duplicate references and unchanged historical decoding before implementation.

## Red-green implementation

- Added three Calls tests first. Their fixture initially used an arbitrary tenant label and then
  a UUID; inspected the actual contract and corrected it to a 16-character public tenant key.
  The expected red run then showed absent plan references and cross-tenant compilation succeeding.
- Added three Persistence tests before implementation. The expected red run showed absent stored
  references and a service rebind after compilation still allowing final prepared-call insertion.
  Existing six service/credential tests remained green.
- Added neutral Engine reference data and the optional participant field. Calls resolves one
  private service snapshot per distinct alias and retains only the stable identity projection.
  The existing factory digests the resulting plan. Raw Engine compilation does not access Calls.
- Web preparation passes its actual compiled plan to the final guard. Persistence caches locked
  snapshots by alias and compares each supplied reference, including duplicates, before the
  existing write callback. Tenant, canonical service, alias, provider, account and credential
  mismatches fail safely; missing references and physically older serialized participants also fail.
- Calls focused tests pass 3/3. Persistence focused tests pass 9/9, including three kinds of
  post-compile rebinding, metadata persistence/digest/privacy, mismatched duplicate references
  and legacy codec preservation. Broad suites and independent review remain in progress.

## Review and cold decoding

- Broader Calls 84 and Persistence 118 tests pass (9 excluded). Independent review requested
  an explicit repository contract for supplied-reference comparison and the same behavior in
  the finite Calls test double. Corrected both; Calls 84 tests pass again.
- Credo flagged nesting and an ignored reduce result in the lock cache. Extracted
  `lock_requirements`/`required_snapshot` without changing lock order or comparison behavior.
- Independent review identified a missing restart check: safe external-term decoding depends
  on the VM already knowing the new participant-field atom. A disposable fresh-VM fetch failed.
  The otherwise identical plan with that field physically removed also failed, and loading only
  Participant/ServiceReference did not fix either case. This exposes an existing cold-codec
  dependency as well as the new field; it is not solely a service-reference regression.
- Inventoried unknown atom names without interning them or decoding unsafely. They belong to
  fixed plan structures, connection/capability/participant enums, prepared audio and transfer
  bindings. A temporary diagnostic initially tried Enum directly on structs; corrected it to
  Map.to_list. That diagnostic error did not alter the application or persisted data.
- Added an automated subprocess regression before changing decoding. A real prepared plan
  returned `unreadable` in a fresh Elixir process. The test also requires an unknown serialized
  atom to remain uninterned. Implemented a fixed data-module loader owned by ResolvedCallPlan;
  Persistence invokes it before the unchanged safe decoder. No stored name controls loading,
  and no provider adapter, application scan or runtime process is started.
- All 10 focused Persistence checks now pass. The actual disposable DB cold fetch and final
  static gates remain in progress; no full carrier-reader completion is claimed.
- The disposable fresh-VM fetch now passes before definition compilation or service lookup;
  the new participant-field atom was absent beforehand. Its legacy/no-field control passes too.
  The harness removes its owned database after each run.
- Follow-up review identified existing optional enum owners and the two JSV 2020-12 vocabulary
  modules used by stored variable validators. Extended the subprocess regression with a bounded
  object/string variable schema and full tool visibility; it failed with `unreadable` before
  adding the fixed Validation/Applicator owners. This retains the existing supported schema
  subset; no arbitrary module or provider loading is introduced.
- The schema case is green after adding those owners. Final Persistence suite: 119 tests,
  zero failures, 9 excluded. Calls: 84 tests, zero failures. Independent final review found no
  blocker in the binding, lock cache, finite loader, fresh-process evidence or scope documentation.
- Format and warnings-as-errors compilation pass; all 172 relative documentation links/anchors
  across the changed documents pass. The subprocess test cleans its own temporary directory so
  encoded plan artifacts are not left in the worktree or staged. Final shared umbrella regression
  follows this reviewed checkpoint; its previously reproduced native Morse failure stays open.
- Strict Credo and unused-lock checks pass. The final cold-process cleanup check passes one test
  (9 excluded) and leaves no encoded plan artifacts in the worktree.

## Final umbrella verification

- At `5c82864`, the full umbrella run passes 1,571 tests, zero failures and 36 exclusions
  (`--preload-modules --max-requires 1 --max-cases 4 --seed 235296`). All five root gates pass.
- Gateway's 413 tests pass. The previously observed native Morse and five-participant audio
  failures did not recur; this pass does not establish their cause. No audio behavior was changed.
- The milestone remains four of seven checkpoints complete. Incoming final insertion, live
  carrier readers and the other recorded unfinished work still prevent full milestone acceptance.
