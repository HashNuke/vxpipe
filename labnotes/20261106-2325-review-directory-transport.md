# Review directory transport

- Scope: Console public Request, Transport, Page and Client modules, focused and
  tagged loopback tests, direct JSV ownership and runtime directory-origin setting.
  Cache, facade, provider management and tenant MCP workflows are later commits.
- Original implementation used red-green tests for each missing module, unknown
  adapters and actual HTTP transport. The latter exposed incompatible Req/Finch
  options; configuration was corrected before the local HTTP test passed.
- Existing JSV dependency is already locked in the umbrella; Console declares its
  direct use without changing versions or the lockfile. Schema builds at compile
  time, so releases do not need runtime documentation files or a remote resolver.
- Independent adversarial GPT-6 Astra xhigh review is in progress. Parent and
  reviewer both found the missing explicit snapshot-revision comparison; reviewer
  also found later-page acceptance for a cursorless first-page request. Recorded
  both as milestone tasks and added regression tests before implementation.
- Red identity tests returned the wrong snapshot and a later page as successful
  (vxpipe-directory-identity-red.log). Added explicit revision and initial-position
  checks without changing valid continuation or empty-page behavior.
- Review also found disabled URI format assertions and request category grammar
  diverging from the published schema. Two more red failures confirmed both
  (vxpipe-directory-schema-red.log); enabled JSV formats and aligned the grammar.
- A broader 39-test worktree directory/loopback lane passed the initial fixes;
  it included cache/inventory tests outside this commit. Timeouts are documented
  as per-phase, not a five-second total lifetime;
  the production cache owns the overall deadline in the next checkpoint.
- Staged re-review found hostless/out-of-range-port MCP endpoints accepted by
  generic URI syntax. The new endpoint regression failed before explicit URI
  host/port checks (vxpipe-directory-endpoint-red.log). Strengthened the byte-cap
  test with oversized valid JSON and an exact response_too_large assertion.
- Current checkpoint: all 23 scoped tests pass (22 unit and one local HTTP).
  Full Console passes 470 tests. Format, warnings-as-errors compile, strict Credo
  and unused-dependency checks pass after the fixes; final milestone-wide
  umbrella acceptance remains tracked in T8. Corrected the staged milestone to
  separate the version accessor from the later facade/browser response field.
- Final adversarial staged re-review precedes commit. A compilation warning in the
  separate MCP-management test fixture was corrected by grouping function clauses;
  that mechanical change remains outside this commit's source scope.
