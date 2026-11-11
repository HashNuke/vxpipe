# Preserve Console state when returning to the browser

- Report: `/api-keys/new` appeared to refresh whenever the browser regained focus.
- Cause: `ConsoleNavigation` listened to `window.focus` and refreshed navigation
  and session data. The new navigation object also invalidated the API-key page,
  reloading its inventory and clearing the selected tenant and one-time key reveal.
- Decision: remove the shared focus refresh. These Console pages load on navigation
  and explicit operations; switching applications should make no requests or reset
  the page. Keep existing permission checks, request-error handling and explicit
  refresh behavior. No caching layer or response comparison is needed.
- Regression: the real App route test failed before the fix with seven requests
  instead of four after focus. It now preserves the name, access type, tenant and
  revealed key without extra requests. Existing revocation/expiry checks now use
  navigation as the trigger, matching the requested behavior.
- Setup: `bin/setup` completed and preserved existing environment configuration;
  no environment-file contents were inspected.
- Verification: 19 focused frontend tests and all 1,066 Console frontend tests
  pass. TypeScript, ESLint for the changed files and the umbrella format,
  warnings-as-errors compilation, strict Credo and unused-dependency checks pass.
- Browser: headless Chrome via `agent-browser`, with production navigation and
  API-key components and a synthetic local API. Checked 1280×900 form and 390×844
  key reveal. Switching tabs produced real window-focus events with request counts
  unchanged (4→4 and 6→6), retained fields/reveal, no document reload, no horizontal
  overflow and no browser errors. This did not create a real API key or require
  access to a signed-in production session. Chrome required `--no-sandbox` on this
  host. Screenshots are temporary local artifacts.
- The full umbrella attempt completed Identity, MCP, Providers, Agent Runtime,
  Call Engine and Calls with zero failures. The kernel then killed its BEAM VM
  during Gateway tests for host memory exhaustion while the QA asset build was
  starting. This is an interrupted run, not a passing full suite. The user asked
  for focused tests only; do not rerun the full suite for this fix.
- Memory finding: the host has 7.6 GiB usable RAM and no swap. RAM-backed `/tmp`
  consumes about 2.3 GiB, chiefly an older 1.9 GiB MCP scratch checkout. The killed
  test VM used about 2 GiB anonymous RSS; the live app remained healthy at about
  354 MiB under its unchanged 1 GiB container limit. Build and verification now
  run sequentially. No unrelated scratch directories were removed.
- The same source/test changes are applied to `qa`; production assets and release
  built successfully there after the interrupted overlapping attempt. The
  project-specific Codex configuration remains exclusive to the main checkout.
- All 19 focused tests pass again in QA. Rebuilt the local Docker image from its
  assembled release and restarted `vxpipe.service`. Both Vxpipe and Caddy are
  active; public `/healthz` returns `ok`. The JavaScript served by
  `https://vitrum.vxpipe.com/assets/admin.js` matches the new release byte-for-byte.
  The container remains limited to 1 GiB and has no OOM flag. Existing runtime
  configuration was loaded privately by the service; no environment files were
  inspected or changed. The temporary browser server was stopped after inspection.
