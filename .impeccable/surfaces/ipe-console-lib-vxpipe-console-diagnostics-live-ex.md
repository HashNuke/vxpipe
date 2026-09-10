---
version: 1
slug: "ipe-console-lib-vxpipe-console-diagnostics-live-ex"
primary_target: "apps/vxpipe_console/lib/vxpipe/console/diagnostics_live.ex"
related_targets: ["apps/vxpipe_console/lib/vxpipe/console/diagnostics_layout.ex","apps/vxpipe_console/lib/vxpipe/console/diagnostics_asset_controller.ex"]
---

# Diagnostics surface brief

Mode: Operate.

Audience: a developer running a Vxpipe sample call locally.
Job: verify that the call path is healthy, distinguish missing observations from failures,
and notice stale or saturated collection without opening logs.
Primary task: scan current runtime health, request/model/speech timing, and safe provider
failure categories while exercising the separate voice console.
Constraints: use only bounded reporter snapshots; retain no event history; keep the voice
console unchanged; expose no conversation payloads or credentials; keep any local failure
fixture fixed and opt-in; work at desktop and mobile.

## Direction contract

THESIS: One live instrument board exposes call-path health; it refuses a generic grid of
detached metric cards.

OWN-WORLD: Operator's Bench neutrals, shallow bordered panels, sans labels, mono readouts,
and green/coral used only for healthy or degraded state.

STORY: The operator sees collection status first, scans runtime and latency, then identifies
failed or missing work, arms one controlled local outcome when available, and can open VM
details or return to the sample.

FIRST VIEWPORT: A compact header and status rail lead into one asymmetric work surface:
runtime and collection at left, timing tables centrally, and failure/outcome ledgers at right.
The two navigation actions sit in the header.

FORM: Direct extension of the established Operator's Bench, structure key
`direct-observability-board`; changed values acknowledge updates without decorative motion.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review,
the verdict, DESIGN.md, and every shipping raster carrying its provenance

Unresolved decisions: none for this bounded milestone surface.

## Finish evidence — background tools

The existing instrument board gained one compact background-tools section rather than a
new dashboard surface or detached card grid. It uses the established ledgers, status colors,
mono measurements, spacing, and empty-state language. It shows only bounded sanitized
aggregates: reservation/mailbox pressure, admissions, terminal duration, and handoff outcomes.
Desktop 1440 px and mobile 390 px Chromium renders were inspected in empty and populated
states; hierarchy remained scannable and no horizontal overflow appeared. The voice-console
surface and design tokens did not change, so `DESIGN.md` requires no update for this extension.

## Finish evidence — remote MCP

Remote MCP visibility extends the central timing column with one established instrument
section, not a detached card surface. It exposes active connections, explicit unavailable
queue pressure, lifecycle outcomes, and discovery/invocation outcomes using the existing
readout and ledger grammar. Desktop 1440 × 1000 and mobile 390 × 844 populated Chromium
renders were inspected; the mobile document remained exactly 390 px wide and tables stayed
legible without horizontal overflow. Scoped accessibility audits returned zero violations at
both viewports, and the browser reported no runtime errors. The review found that the
diagnostics-only Fault Coral value had drifted from the documented design token and failed
small-text contrast; restoring the documented token resolved the violation. No new token was
introduced, so `DESIGN.md` requires no update.
