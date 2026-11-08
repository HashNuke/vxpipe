# Queued catalog refresh

Date: 2026-11-08. Baseline: `6d128154` on `main`.

## Request and confirmed rule

Update the participant MCP milestone/design with Sidekiq-style durable background
jobs: a periodic job selects stale tenant catalogs and enqueues one job per saved
connection. Track `refresh_scheduled_at` and `refreshed_at`; use application config
for expiry, with no new environment variables. The user confirmed via clarification:
recent scheduling suppresses duplicates, and stale catalogs can be reconsidered
when scheduling is missing or at least 30 minutes old. This resolves the original
wording's ambiguous comparison direction.

## Research and choices

- Current tenant connection records already store catalogs. Static setup discovers
  before successful create; OAuth completion discovers after token exchange.
  Manual refresh exists. Dedicated refresh timestamps and the due-row job sweep
  do not exist; the optional embedded refresher reads application configuration.
- Selected Oban with the existing PostgreSQL Repo as the planned standard queue.
  Official documentation reports 2.24.2; inspected transactional insertion,
  uniqueness, workers/timeouts, Cron and Lifeline. `Oban.Plugins.Cron` is deprecated
  in favor of `Oban.Cron` in those docs. No dependency was installed or pinned here.
- Oban insertion uniqueness is not exactly-once execution, and Lifeline's time-
  based rescue can duplicate attempts. Short transactional row locking/conditional
  updates establish scheduling and publication authority; network discovery stays
  outside transactions. Ordinary retries/recovery/pruning remain library-owned.
- Planned Oban adapter/workers/migrations belong to Persistence; Calls owns trusted
  catalog workflow and MCP owns transport. Existing Console-hosted protocol helpers
  may need narrow extraction; no inverse Persistence-to-Console dependency.
- The two timestamps are independent: scheduling changes only with a new durable
  job; success changes only with a complete accepted snapshot. Initial/manual/no-
  change/valid-empty success counts; enqueue failure, retries and token renewal do
  not manufacture freshness. Existing unknown-age snapshots are retained and due.
- Thirty-minute recovery checks incomplete jobs before replacement, so queue delay
  does not create duplicates. Obsolete generations, scheduling stamps and results
  older than a completed manual/job refresh are rejected. No catalog-based grant
  widening or automatic mutation of running-call schemas.
- Clarified session identity with a fresh owner PID/reference and the P1/P2/P3
  example. Defined retirement as stopping an activation and freeing its resources.
  Broader legacy embedded-refresher redesign is recorded separately from this
  authorized saved-tenant maintenance workflow.

## Independent amendment review

GPT-6 Astra xhigh reviewed the queue and application boundaries separately from
the original milestone approval. Two planning gaps were identified and corrected:

- A full first batch of delayed jobs could starve later due connections. The
  sweep must exclude incomplete jobs before its limit or make bounded keyset
  progress; acceptance now covers a backlog larger than a batch.
- Freshness doubles as the publication guard. Require a NULL-safe exact comparison
  against the observed timestamp and strictly advance successful refresh time at
  microsecond precision even under an equal/backward database clock. Acceptance
  includes competing held results under a fixed clock.

Also clarified Oban's successful uniqueness-conflict return: only an actual new
insertion advances scheduling time. Incomplete-state matching excludes completed
job history. These were specification gaps; no runtime defect was reproduced.
The reviewer re-read the amendments and approved the planning checkpoint with no
remaining blockers on 2026-11-08. This is design/source review only.

## Verification

- `git diff --check` passed. Checked all 211 local links across the five changed
  documents, including heading anchors, plus code fences, final newlines and the
  absence of local absolute paths. All checks passed.
- The index still has 57 milestones and 44 completed entries; participant-owned
  MCP sessions remains unchecked. All implementation/acceptance checklist items
  in this milestone remain open; only specification-review items are complete.
- Independent amendment review passed after the corrections recorded above.
- Runtime implementation, dependency changes, database migrations and all new
  milestone acceptance remain unimplemented. No test/deployment result is implied
  by this documentation update. Commit/push is authorized by the user's standing
  instruction for repository changes.
