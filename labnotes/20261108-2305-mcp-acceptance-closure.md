# MCP acceptance closure

Previous goal turn made authoritative progress: committed and pushed catalog jobs
as `0150c974`; all five root gates passed (5,094 tests, zero failures, 363 excluded,
seed 412417). The milestone begins this checkpoint at 22/29 complete. No external
blocker is present. Reuse the existing fixtures to close remaining composition,
teardown, capacity and final acceptance gaps; change production only for a
reproduced project-owned failure.

The first combined saved-grant probe passes disconnect, replacement and local
revocation for two real sessions. Its expiry case initially advances the test
clock beyond both the original and the fixture's new five-minute token lifetime,
so a second renewal is correctly attempted. The token fixture now permits a
longer issued lifetime for this clock-controlled case. A second failure exposes
an obsolete fixture cleanup sequence: it explicitly disconnects ExMCP before
calling the now remotely-cleaning owner retirement path. The fixture now uses
owner retirement directly, exercising the real non-renewing cleanup contract.
Neither finding required a production change.

The previous phone timestamp failure is independently reproduced with only the
archive subscriber paused. Exact engine completion and all three registered
resource roots DOWN/acknowledged precede durable cleanup; the resumed archive
subscriber records closure 14,523 microseconds later. The saved call is ended and
its end time matches the close fact. Astra review identifies an invalid test
ordering assumption, not early cleanup. Preserve every termination check and
compare the saved end time to the archive fact instead. Correct the older
milestone's unconditional timestamp-order claim as well.

## Acceptance evidence

The saved-runtime/shared-grant/phone/cross-node lane passes 20 tests, zero
failures, seed 344909. Two real sessions share durable renewal authority but
retain distinct wire state. POST/GET use the refreshed credential; valid-current
cleanup sends DELETE, while expired cleanup skips it without renewal. Saved
disconnect/replacement and local revocation cover both holders. Saved WebRTC
hangup and all three phone paths observe MCP descendant termination and peer
stream closure through durable ended state.

The Call Engine live lane passes 21 tests, zero failures, seed 816637. It adds
late POST/GET release after room-incarnation replacement, exact stale-handle
fencing, three rounds of four concurrent initializations, and a provider cap of
one session that rejects transfer preparation while preserving a usable source.
The opening-worker observation was added after this run; its final rerun and
published counts are recorded below. Existing re-entry, recovery, timeout and held
POST/GET/DELETE cases remain in the same lane.

`bin/test-platform-mcp` now starts and retires an actual outbound-tool call,
then uses the same external SDK session again at each inbound mount. The first
attempt passed embedded but failed on Console because fixture cleanup used the
module rather than its named supervisor child ID. Inspecting the actual child
spec reproduced the mismatch; cleanup now uses the name and checks both results.
The final runner passes embedded, Console and Gateway, all 17 tools, three
official server scenarios, whole-BEAM restart and accelerated idle expiry.
This harness correction required no production change.

Independent GPT-6 Astra xhigh review finds no valid issue in the acceptance diff
through the shared-grant, phone, room-incarnation and capacity cases. The final
Cron/platform increment and completion evidence were then reviewed and approved.
All changes
in this checkpoint are tests, fixtures and documentation; no product behavior,
UI, protocol profile or architecture is added.

The final Call Engine run passes 36 tests, seed 451536, including the added
opening-worker observation: four concurrent sessions have 12 workers during
initialization, then two workers each at readiness; all terminate and the count
returns to zero in each of three rounds. Open measurements range 3.235–20.497 ms,
ordinary close 0.985–1.915 ms. These are controlled local fixtures with SSE disabled,
not production percentiles. Active/held SSE cleanup is covered separately.
The complete MCP protocol/ownership/privacy lane passes 293 tests, seed 441392,
including official client conformance, corrected SSE recovery and Everything.
Actual configured Cron-to-sweep-to-refresh passes in the 13-case catalog-job lane,
seed 905562; the independent reviewer also inspected the successful output.

The expanded Console lane initially passed 34 of 35 cases, seed 154888. Its
changed-schema case received the expected 503 but read `:admitting` immediately
instead of `:failed`. The unchanged seven-case file and the exact unchanged
35-case rerun both pass on that seed. Source review identifies an asynchronous
Gateway projection: HTTP starts `mark_failed` under the admission task supervisor
and returns before the write completes. The helper needs a task-completion
barrier, not a product admission change. A separate `:admission_error` contract
intentionally preserves persistence uncertainty and must not be altered.

## Verification method

The user asked to reduce duplicative workflow. For this backend-only checkpoint,
the five operator scenarios are exercised through the existing controlled local
harnesses and their observed process, socket, API and database evidence. This
avoids a second hand-driven enactment of the same behaviors while retaining every
runtime acceptance condition. The Console harness authenticates requests and
drives real WebRTC data channels against controlled model/MCP/carrier fixtures;
the platform runner uses real HTTP listeners and the official external SDK.
No browser visual walkthrough, live-provider test, deployment or new UI approval
is claimed. The milestone records this verification-method decision separately
from implementation progress.

GPT-6 Astra xhigh reviewed that five-scenario map and found no missing backend
behavior. Its scope clarification explicitly distinguishes programmatic local
Console/WebRTC and synthetic identities/providers from browser, live-provider or
deployment verification. It does not change product acceptance behavior.

Commands (run from the named child application unless noted):

- Persistence: `mix test test/integration/mcp_catalog_jobs_test.exs --include integration`.
- Call Engine: `mix test test/vxpipe/call_engine/remote_mcp/live_call_test.exs test/vxpipe/call_engine/remote_mcp/integration_owner_test.exs test/integration/participant_mcp_sessions_test.exs --include integration`.
- MCP: `mix test test/vxpipe/mcp test/integration --include integration`.
- Console: `mix test test/integration/saved_mcp_runtime_test.exs test/integration/saved_mcp_telephony_test.exs test/integration/saved_mcp_transfer_test.exs test/integration/saved_mcp_inflight_test.exs test/integration/saved_mcp_boundaries_test.exs test/integration/saved_mcp_catalog_jobs_test.exs test/integration/saved_mcp_catalog_audio_test.exs test/integration/mcp_shared_grant_sessions_test.exs test/integration/saved_mcp_shared_sessions_test.exs test/integration/mcp_runtime_nodes_test.exs --include integration --seed 154888`.
- Root external acceptance: `bin/test-platform-mcp`.
- Root gates: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix deps.unlock --check-unused`; all pass. The final
  `mix test` passed after the clean focused lanes, as recorded below.

## Completion

The independent gated projection probe passes (one case, seed 154888): it holds
the real `mark_failed` worker, observes HTTP 503 with durable `:admitting`, then
releases and acknowledges the write to `:failed`. The helper now observes the
already-started projection tasks terminate before retaining its existing durable
state assertions. Its seven affected Console cases pass on the same seed. No
application behavior changes and no speculative admission-path fix is added.

All five root gates pass. The complete umbrella run finishes with 5,094 tests,
zero failures and 371 exclusions, seed 157471. After that run, only the helper
barrier and documentation changed; the seven affected cases and format,
warnings-as-errors compile, strict Credo and unused-dependency checks pass again.
No source-cutover or speech state machine changed, so Lean is not required.

All 29 implementation items now have evidence. The design, milestone and index
are synchronized. Verification uses the existing local infrastructure; it does
not deploy a release, republish the directory or supply separate workflow approval.
