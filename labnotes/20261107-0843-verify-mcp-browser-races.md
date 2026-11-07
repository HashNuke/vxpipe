# Authenticated MCP discovery races

Complete the remaining T4a browser URL/revision and close/reopen checks with the
real compiled Console, persisted identity/session and controlled local MCP/OAuth
peer. A new isolated checkout starts at c2853fb3; run its bin/setup before using
its assigned databases and ports. Do not reset the main checkout's installation.

Use headless Chrome through agent-browser at desktop/mobile viewports. To force
late browser responses, hold actual same-origin discovery fetch results in local
page instrumentation, then release after URL edits, manual same-URL edits or modal
closure. Preserve response bodies and status; this is UI race acceptance, not a
claim about physical backend cancellation or real network timing. Record actual
request/response revision and visible state without capturing credentials.

The prior checkpoint's full same-seed umbrella rerun remains active. No separate
test suite is launched concurrently against its test database. The browser checkout
uses its own development database, secrets and ports.

Setup completed successfully in the isolated `integrations-browser-acceptance-20261107`
checkout. Created the installation, Superadmin and tenant through the actual UI;
used Chrome with a locally trusted CA, the fixture hostname mapping and the
container's required `--no-sandbox` launch setting. Browser certificate checks
remained enabled. An attempted browser-state restore failed CA validation; a fresh
owned browser session with the same CA and an ordinary login worked. Private state,
credentials, keys and screenshots remain in ignored `.vxpipe/browser/`.

The final bounded pass ran at 1280×900 and 390×844 with the existing CIMD peer.
All 11 checks passed at each viewport:

- Hold URL A's actual HTTP 200 OAuth/CIMD result, change to URL B on the same peer
  (`/unavailable`), observe B's actual unknown result, then release A. B's URL,
  recovery message and unselected method remain unchanged.
- Before releasing a same-URL result, manually choose Own client and edit client ID,
  authorization URL, token URL and scopes. All edits remain after successful
  discovery, while untouched defaults populate normally.
- Close and reopen after those edits: the new draft is empty. Separately hold a
  response, close its dialog, open a fresh one and release the old result. The new
  draft remains empty with Connect disabled.
- Enter temporary header values, switch Custom headers → Bearer → Basic, and
  inspect the expanded additional-header area. Inactive headers and credentials
  clear. Basic → No authentication → Basic also starts with empty credentials and
  headers. Empty active credentials produce inline validation without a save request.
- Changing the URL clears the method and credential fields; choosing Basic again
  cannot restore the previous URL's username or password.
- The expanded mobile form has no page-level horizontal overflow, scrolls to its
  fields and keeps its footer visible. Screenshots of URL failure, manual prefill,
  fresh reopened draft and cleared credentials were inspected at both sizes.
- Inventory remains empty and the browser records no mutation requests other than
  read-only discovery. The peer counters contain no registration, token exchange,
  authorization or tool invocation, including earlier exploratory passes.

The final trace contains 12 real discovery responses. Held URL-change results
(IDs 1/7) and closed-draft results (4/10) were aborted at release; same-URL edited
results (3/9) were not. Every response echoed its requested endpoint and revision.
The wrapper forwards the original Response unchanged after reading a clone for
public evidence. It does not replace payloads/statuses, strip the AbortSignal or
simulate a successful backend. It tests late delivery to the UI, not physical
cancellation of already completed remote work or third-party interoperability.

Local evidence files are `all-discovery-trace.json`, `race-counts-final.json`,
`desktop-checks.json`, `mobile-checks.json`, and `desktop-*`/`mobile-*` screenshots
under the acceptance checkout's ignored browser directory. The driver uses
agent-browser for all UI interactions and waits for request IDs and visible states.
It must wait for the Connect other MCP button to become enabled after the real
inventory reload on close; an immediate click during that disabled state is not a
reopen. Early instrumentation errors (tuple counter keys, a relative output path,
and accidentally changing the fixture hostname along with its path) were corrected
before the final complete pass. No production UI change was needed.

Independent Astra evidence/source/rendered review is complete with no reproduced
bug or blocking evidence gap. The reviewer inspected all eight images, both drivers,
the trace/counters and matching production source, and supports closing T4a and the
narrow race task. This pass checks matching revision echoes; it does not inject
malformed/mismatched revisions, which remain covered by separate hook/API tests.
The full root suite for the
separately committed publication-monitor test correction remains active; the Calls
child now passes all 356 tests. This browser checkpoint does not close listed,
retained recovery, independent outage, conformance or public release acceptance.

Final root verification passes all five gates: 4,991 tests, zero failures and 261
exclusions (seed 774698). The preceding failure/correction evidence is recorded in
[publication monitor synchronization](20261107-0850-stabilize-publication-monitor.md).
The remaining milestone acceptance and release gates stay open.
