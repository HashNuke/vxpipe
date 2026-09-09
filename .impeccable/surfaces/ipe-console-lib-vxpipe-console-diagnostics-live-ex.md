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
console unchanged; expose no conversation payloads or credentials; work at desktop and mobile.

## Direction contract

THESIS: One live instrument board exposes call-path health; it refuses a generic grid of
detached metric cards.

OWN-WORLD: Operator's Bench neutrals, shallow bordered panels, sans labels, mono readouts,
and green/coral used only for healthy or degraded state.

STORY: The operator sees collection status first, scans runtime and latency, then identifies
failed or missing work and can open VM details or return to the sample.

FIRST VIEWPORT: A compact header and status rail lead into one asymmetric work surface:
runtime and collection at left, timing tables centrally, and failure/outcome ledgers at right.
The two navigation actions sit in the header.

FORM: Direct extension of the established Operator's Bench, structure key
`direct-observability-board`; changed values acknowledge updates without decorative motion.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review,
the verdict, DESIGN.md, and every shipping raster carrying its provenance

Unresolved decisions: none for this bounded milestone surface.
