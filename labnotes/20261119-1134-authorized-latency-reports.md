# Authorized latency reports

Checkpoint D starts at the Calls boundary. Separate report/run-turn operations
reuse CallReadAccess and the existing LatencyRepository port. Tenant scope comes
from authority, never request options. Defaults are50 rows, maximum100, with bounded
identifiers/cursors. Full-call summary is fetched independently of the selected run
page; persisted revisions and profiles are preserved. Run coverage uses the existing
freshness/loss policy. Unknown runs and storage errors propagate as diagnostic read
errors without touching conversation/history workflows.

Turn pagination stays within the existing100-row port limit. A full final page may
return a cursor whose successor is empty; that avoids an over-limit101-row query.
No offset-based pagination or in-memory full-report aggregation is introduced.

Six focused contracts failed because the facade operations did not exist, then
passed6/0 after implementation. Coverage includes denied authority, cross-tenant
and foreign-run reads, paging, stale heartbeat, full-report summary, malformed
requests and storage outage. Console routes, runtime wiring, JSON presentation and
core/UI state are not implemented by this checkpoint; D remains unchecked.

Calls report/inspection/coverage focused selection passes18/0. Existing real
Persistence latency adapter tests pass17/0, including tenant isolation, cursor
pages, all-row summaries and unavailable storage. Formatting, compilation with
warnings as errors and strict Credo pass. These checks do not claim a new end-to-end
HTTP read path; that is the next integration checkpoint.
Independent Astra xhigh source review is clean for the Calls boundary. No additional
Console/composition coverage is claimed by that review.
