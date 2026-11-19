# Diagnostics browser persistence

## Acceptance scope

Added a tagged Console browser integration test for Admin and Superadmin using
real browser-session login, the production Endpoint and compiled frontend assets,
and real Persistence settings reads/writes in a shared SQL sandbox transaction.
Bandit binds an ephemeral loopback port; browser sessions, server and database
transaction are cleaned up. No production setting, provider connection or call is
used. This is local acceptance of production code, not a deployed live-call test.

Each role enables then disables the checkbox with Space, fully reloads the page,
and verifies both the rendered value and durable revision. Superadmin alone sees
the independently loaded Installation URL form. A real authenticated second PATCH
advances the saved revision while the current UI is stale; the stale UI save
must show a conflict and leave the newer database value intact. On mobile, a
bounded real Tab traversal reaches Reload; Enter reloads the saved value, and
Space can save again. Another full reload verifies the final disabled revision.
Deleting the settings row within the sandbox then produces a real storage failure:
the UI keeps the last confirmed value, disables further saves and reports error.

The backend currently returns saved state without an effective-status proof. The
test requires the honest unavailable status after reload. Earlier reviewed
Storybook cases cover simulated applying/pending states; they do not establish a
production acknowledgement. The separate distributed-status task remains open.

## Development and review evidence

This adds acceptance for existing behavior; no runtime implementation changed.
The first fixture run rejected legitimate response audit fields by comparing the
whole JSON object. It now matches the required value/revision/status fields.
The next fixture issue was the browser driver's unsupported `find ... focus`
action. Its `focus button:has-text(...)` alternative also silently left focus on
BODY, reproduced on the existing Storybook page. The test now traverses real Tab
stops and asserts the focused button's label before Enter instead of relying on
that selector extension. No speculative UI fix was made.

Independent Astra review reproduced one race: a ready Diagnostics checkbox does
not imply the separately fetched Superadmin URL settings have loaded. A focused
frontend probe held only the URL response, proved the checkbox was ready while
the URL input was absent, then released it and verified the URL appeared. Root
reproduced the same expected failure. The browser test now explicitly waits for
the URL input for Superadmin; Admin still must have no URL input.

- `mix assets.build` passes; assets used are current production entrypoints.
- Final focused browser test passes 2/2, seed 509203, 6.7 seconds, after the
  URL-readiness correction. Run from Console with:
  `mix test test/integration/diagnostics_settings_browser_test.exs --include integration`.
- Root format, warnings-as-errors compilation, strict Credo and unused-lock checks
  pass. No full-suite or live-provider run; no deployment/restart.
- Headless Chrome captures inspected at 1440×1000 and 390×844: readable Admin and
  Superadmin settings, role-specific URL controls, saved state after reload,
  mobile conflict and recovery. No horizontal overflow. Screenshots use synthetic
  local account data and stay under `/tmp/vxpipe-diagnostic-settings-*.png`.
- Independent Astra xhigh final review is clean after the URL-readiness fix;
  independent browser rerun passes 2/2, seed 758359, 6.6 seconds.

This closes the C settings-page/browser acceptance task. It does not
close cross-node applied/disable semantics, active-call settings acceptance,
measured overhead, accuracy, provider/live browser acceptance or final gates.
