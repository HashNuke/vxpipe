# Review directory cache

- Scope: bounded public-page cache, its worker supervisor and Console ownership.
  Existing client/schema validation is committed separately; inventory and tenant
  connection state are not stored in this cache and remain later checkpoints.
- Original implementation used red-green tests for cache creation, supervision
  ownership, negative monotonic clocks and exhausted Task.Supervisor capacity.
  Independent GPT-6 Astra xhigh source review found no confirmed runtime defect,
  but identified unproven coalescing, stale-data and resource/lifecycle claims.
- Strengthened coalescing with a receive trace plus a cache acknowledgement before
  releasing the worker; previously the second caller could see a normal fresh hit.
  Added actual cached/expired refresh failure, byte eviction/oversize non-storage,
  waiter/worker capacity, crash/timeout recovery and owned restart-boundary tests.
- First focused run exposed an existing fake-clock test race: Cache.fetch replies
  before cache storage completes. Advancing the clock immediately could change
  the stored expiry. Added a system acknowledgement before advancing test clocks;
  no production change or sleep is needed. Local log: vxpipe-directory-cache-review-tests.log.
- All 14 focused tests pass on the original failing seed; full Console passes
  476 tests. These are stronger tests of existing behavior, not new runtime
  behavior requiring an initial red test. Static format, compile, strict Credo
  and unused-dependency checks pass. A second formatting pass was needed for
  multiline anonymous-function arguments. Independent staged source review found
  no blocking issues; clarified its suggested 304 wording to mean missing cached
  content. Final staged review precedes commit; milestone-wide acceptance remains open.
