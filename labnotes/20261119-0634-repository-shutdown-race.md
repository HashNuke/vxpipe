# Repository shutdown race

The full umbrella gate (seed631449) failed when OAuthAttemptStore.locate raised
ArgumentError from Ecto's query-cache ETS lookup during repository shutdown.
Independent Astra review reproduced the same trace by suspending asynchronous
Ecto registry cleanup, stopping a supervised repository, then invoking the real
store through its stopped PID. The query cache was gone while registry metadata
still resolved. Synchronizing the original test would conceal a production race.

The retained regression failed before the fix. RepositoryBoundary now recognizes
only ArgumentError with immediate ETS lookup and Ecto.Query.Planner.query_lookup
frames and a reference identifying a nonexistent table. Other errors still
propagate, including generic ArgumentError and unrelated missing ETS tables.
This preserves the fixed unavailable result during the legitimate shutdown window.

Focused boundary/OAuth attempt/grant tests pass33/0 with seed631449. Static root
checks pass; independent Astra xhigh review of the final diff is clean (33/0). A new umbrella
run includes this fix and the reused diagnostic consumer checkpoint.
