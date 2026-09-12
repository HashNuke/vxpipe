# Context compaction and fallback

## Scope

Implement milestone 22: bounded model-context compaction plus only the
provider-native routing/fallback configuration supported through ReqLLM. This
work must not introduce a Vxpipe-managed provider chain or give summarized text
tool, policy, variable, or permission authority.

## 2026-09-12 — budget boundary checkpoint

- Confirmed the active runtime already represents every input class in one
  normalized `ModelRequest`: committed/staged messages, tool definitions,
  unresolved invocation state, transient authorized call-variable projection,
  and request correlation. The token counter therefore receives this complete
  request rather than a partial history list.
- Added a focused `ContextBudget` value. Output capacity is reserved before
  calculating the usable input budget. The compaction trigger is the ceiling of
  75% of usable input; the strict below-50% target is
  `div(usable_input_tokens - 1, 2)`.
- Kept counting behind the separate `InputTokenCounter` contract and bounded it
  through `RequestBudget`. This avoids claiming that a generic character
  estimate is exact for every provider/model and keeps counting work outside
  the session process.
- Invalid/unavailable counters produce the typed
  `:input_token_count_unavailable` outcome. They never authorize a provider
  request with an unmeasured context.

Red evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/context_budget_test.exs
# 5 tests, 5 failures: ContextBudget and RequestBudget were absent
```

Green evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/context_budget_test.exs
# 5 tests, 0 failures
```

The first milestone checklist item remains open until a fake compactor consumes
the decision and proves replacement against realistic protected conversation
entries.
