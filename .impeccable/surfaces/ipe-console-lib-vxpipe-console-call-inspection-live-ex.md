---
version: 1
slug: "ipe-console-lib-vxpipe-console-call-inspection-live-ex"
primary_target: "apps/vxpipe_console/lib/vxpipe/console/call_inspection_live.ex"
related_targets: ["apps/vxpipe_console/lib/vxpipe/console/call_inspection_components.ex","apps/vxpipe_console/lib/vxpipe/console/call_inspection_detail_live.ex","apps/vxpipe_console/lib/vxpipe/console/call_inspection_detail_components.ex","apps/vxpipe_console/lib/vxpipe/console/call_inspection_layout.ex","apps/vxpipe_console/lib/vxpipe/console/call_inspection_styles.css","apps/vxpipe_console/lib/vxpipe/console/operator_sign_in_page.ex"]
---

# Call inspection surface brief

Mode: Operate.

Audience: a developer diagnosing tenant calls.
Job: select a call, correlate its permitted facts and variables, and distinguish live
accepted state from persisted history without affecting the call.
Constraints: read-only, tenant-authorized, bounded and paginated; inert payloads; explicit
empty, denied, ended, lagging, incomplete, and unavailable states; desktop and mobile.

## Direction contract

THESIS: One revision matrix connects each call to its evidence; it refuses detached
dashboard cards.

OWN-WORLD: Operator's Bench paper, ink status rails, shallow divided panels, sans actions,
mono data, and green/coral/violet/blue only for operational meaning.

STORY: Scan calls, select one, follow its sourced ledger, inspect exact evidence, then
compare variable revisions and archive condition.

FIRST VIEWPORT: Header and status strip lead into a full-width call table; the selected
call opens below as a 65/35 ledger/evidence workbench with a thin variables-diff footer.

FORM: Revision Matrix, structure two of seven, seed `37ccdd1d`; delegated comp selection
`.impeccable/mocks/call-inspection-workbench.png`; row and event selection preserve context.

FINISH: SHIPPED — the final reviewer confirmed all six material fixes resolved. Desktop
evidence `.impeccable/review/desktop.png` and mobile evidence
`.impeccable/review/mobile.png` show no horizontal overflow; the detector pass was empty;
DESIGN.md and its sidecar were refreshed from the finished surface. Disposition: ship.

Unresolved decisions: none for this milestone surface.
