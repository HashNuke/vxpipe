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

## 2026-09-12 — protected conversation checkpoint

- Added snapshot selection over committed `Conversation.Entry` values. Permanent
  system/transfer entries and a configurable recent tail are protected.
- Entries containing a tool call or result whose invocation ID is currently
  pending are protected as one relationship. Selection is a contiguous old
  prefix and therefore never reorders a summary around protected work.
- Replacement verifies the complete snapshotted prefix against current state.
  Entries appended after the snapshot are retained; a changed prefix returns
  `:stale_compaction_snapshot` without attaching the summary.
- A derived summary is structurally an assistant message with no tool calls or
  tool-result identity. Its fixed envelope identifies it as untrusted historical
  data with no instruction, policy, tool, variable, or permission authority.
- Compacted durable entries carry their prior correlations in the derived entry,
  preserving the existing interruption/recovery query without retaining their
  full model-facing text.

Red evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/conversation_compaction_test.exs
# 5 tests, 5 failures: ConversationCompaction was absent
```

Green evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/conversation_compaction_test.exs
# 5 tests, 0 failures
mix test
# 69 tests, 0 failures (2 excluded)
```

The selection/replacement primitive does not call a summarizer. The first
milestone checklist item remains open until one bounded fake-compactor attempt
is orchestrated and the final request is remeasured.

## 2026-09-12 — fake compactor orchestration checkpoint

- Added `ContextPreparation`, which measures the full normalized request and
  makes no compactor call below the threshold.
- A triggered attempt snapshots only eligible conversation entries, measures the
  protected request, and refuses to compact when protected/current content fills
  the usable input window.
- The `CompactionRequest` contains only selected authorized messages, their
  source correlations, the request correlation, and a maximum summary-token
  allowance. It has no tool definitions, pending invocation projection, Call
  Variables projection, executor, or other execution authority.
- The `ContextCompactor` callback runs once behind a bounded runner. Its result
  carries separately bounded summary text, observed usage, and safe provider
  metadata.
- After replacement, the entire model request is rebuilt with the unchanged
  tools, pending invocation state, transient variables, current work, and recent
  messages, then measured again. If an achievable below-half target is missed,
  the result is rejected as `:compacted_context_too_large`.
- Failures return the original immutable conversation to the caller; no partial
  compacted state is committed.

Red evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/context_preparation_test.exs
# 5 tests, 5 failures: ContextPreparation and CompactionResult were absent
```

Green evidence:

```text
cd apps/vxpipe_agent_runtime
mix test test/vxpipe/agent_runtime/context_preparation_test.exs
# 5 tests, 0 failures
mix test
# 74 tests, 0 failures (2 excluded)
```

The first implementation checklist item is now complete. The production
summarizer/model selection, conservative token accounting, and runtime-session
integration remain open.
