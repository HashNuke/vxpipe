# Configure browser outage startup scenarios

The ignored TLS proxy and IEx port overrides proved manual outage behavior but did
not provide a reusable committed launcher. Add startup-selected independent
directory healthy/503/429 and local-status healthy/unavailable states to the guarded
development launcher. Healthy directory requests must forward to the real publisher;
do not synthesize a catalog. Controls should preserve exact repository restoration,
allow explicit cold-cache reset, and expose only public counters. Keep the proxy
bounded and anonymous. No production endpoints or deployment settings change.

Write the focused contracts first: fault isolation/recovery, version and ETag
forwarding without cookies/authorization, startup validation, bounded responses,
and the existing development guard. The initial red run also exposed an incorrect
relative launcher path in the test; corrected that fixture path before implementation.

The corrected red run has four expected missing-control failures and a passing
existing-launcher guard. Five tests now pass. Implementation iterations corrected
a helper name conflicting with Plug.Conn.chunk/2; the test setup also needed its
tenant repository port and semantic keyword-map comparison, because port restore
can reorder keywords without changing configuration. No product defect is inferred
from those fixture corrections.

Astra independently reran all five cases (seed 774698), reviewed the implementation
and found no reproduced bug or required correction. Unit tests use Req.Test; real
publisher/TLS/browser acceptance is recorded separately below.

The actual updated launcher starts with directory unavailable/local status healthy
against the local Go publisher. A cold AI request returns HTTP 200 fallback with
11 installed AI entries; desktop/mobile show the unavailable notice and functional
Connect controls. The first mobile capture caught loading and was replaced after
the actual cards appeared. Switching directory to healthy and local status to
unavailable yields typed inventory HTTP 503 plus safe Retry connections, while
a direct normal-certificate TLS request to the new proxy still returns the real
publisher category catalog with HTTP 200. Both viewports were inspected. Restoring
local status and clicking Retry recovers the actual Calendar listings.

Selecting directory rate_limited and explicitly resetting the cache proves real
HTTP 429 cooldown. After the fallback renders, Retry directory and a distinct
search query leave public proxy counters unchanged: requests 8, forward attempts 4.
The latter count includes preceding healthy requests. The search response stays
HTTP 200 with directory_error rate_limited. Receipts and screenshots are retained
under ignored browser/listed-directory artifacts. Literal local-status-unavailable
startup and final root gates are still in progress.

A second actual launcher invocation starts with directory healthy and local status
unavailable from environment variables. Its initial public snapshot confirms those
states; authenticated inventory returns the typed HTTP 503 while the actual Go
catalog through the new TLS proxy returns HTTP 200. Restoring local status through
the documented control and clicking Retry recovers listings; final desktop/mobile
Calendar screenshots were inspected. This completes real startup/control acceptance,
including the separate startup choices. No browser interception or fabricated
success payloads were used for these checks.

Format, warnings-as-errors compilation, strict Credo and unused-lock checks pass.
The full root test run remains active; its result will be recorded separately.
These fixture/test changes do not alter source-cutover or speech state machines,
so the Lean lane does not apply to this checkpoint.

The root run was deliberately interrupted during Gateway after the later inventory
browser pass reproduced the separate uppercase-search bug. Earlier root checks and
children had passed; this interrupted run is not counted as complete. A fresh full
run must include the search correction. The interruption was issued explicitly
through the owned PTY, unlike the earlier unexplained SIGTERM checkpoint.
