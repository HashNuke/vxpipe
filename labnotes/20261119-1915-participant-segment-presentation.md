# Participant segment presentation

## Implementation

The shared diagnostics view now shows local acoustic segments inside expanded
canonical turns: estimated start/end, confirmation offsets, sample positions,
epoch, uncertainty and reasons. Multiple segments never become extra conversational
turns. Run-level speech outside recorded turns is a separate native disclosure,
collapsed by default. Legacy absent evidence is unavailable; observed empty evidence
says no segments recorded. Missing times are never rendered as zero.

ParticipantSegments stories exist for the shared view, admin call details and debug
Workbench. They show two independently identified human STT sources, continuous
caller run/source/clock across two response commands, fallback vs operational reuse,
an operational reset with missing endpoint, and bounded unattached evidence with
omitted count. Participant IDs match each host's existing human fixtures. These are
synthetic presentation fixtures, not live timing or operational transfer evidence.
The earlier configured transfer checkpoint supplies the actual transfer proof.

The section and per-turn rows retain collapsed defaults, right-side chevrons and
top-aligned headers. On mobile, expanded prose stays inside the viewport while the
four-column segment table remains keyboard-scrollable. Existing theme tokens apply.

## Red/green and review

Three new UI contracts initially fail while 23 existing cases pass. After the
component implementation all 26 pass. Independent review reproduces two issues:
a reset fixture inherited partial_start as its latency reason, and a lower run
revision could erase newer unattached evidence on refresh. The owned refresh test
also fails before the fix. Correct the fixture reason and merge retained run records
by ID/revision within the incoming page; same-revision reads still update derived
coverage, and incoming summary/cursor remain authoritative. Independent probes then
pass 3/3, including the coverage positive control.

Final focused core/React latency, paging and call-details selection passes 43/43;
Console host/fixture/API selection passes 18/18. Workspace build/typecheck, Console
typecheck, root format, compile warnings-as-errors, strict Credo and unused-lock
checks pass. No runtime speech-state change requires a Lean run.

## Rendered evidence

Used agent-browser headless Chrome at 1440px desktop and 390px mobile for both hosts,
including two-participant switching, caller continuity, reset gap, absent/empty
segment evidence, omitted segments, collapsed defaults and legacy rows. Also checked
the debug host's light theme. Initial mobile prose exceeded the visible table area;
one layout correction keeps it at 342px within the 390px viewport. Final screenshots:

- `/tmp/vxpipe-segments-admin-desktop-final.png`
- `/tmp/vxpipe-segments-admin-mobile-final.png`
- `/tmp/vxpipe-segments-debug-desktop-final.png`
- `/tmp/vxpipe-segments-debug-mobile-final.png`
- `/tmp/vxpipe-segments-admin-legacy.png`
- `/tmp/vxpipe-segments-debug-legacy-light.png`

Both mobile pages measure document width 390px. All table headers remain top-aligned.
The unattached summary opens with Enter and has a visible focus outline. The inner
segment region accepts keyboard horizontal scrolling (342px viewport, 397px content,
32px observed scroll offset). No screenshot-only success substitutes for assertions.
Independent final visual review is clean across all six captures; its retained
latency/core selection also passes 34/34. The D participant/segment extension is
complete. Remaining C acceptance and E/F keep the milestone/index open.

Storybook serves on localhost:6007 and the existing Tailscale-only TCP forwarding
at 100.65.185.95:6007. Restarting required briefly stopping that forwarding because
Storybook's port probe sees the Tailscale listener; it was restored after startup.
The updated stories were verified through the Tailscale address. Production/dev
vxpipe.service was not restarted or deployed. No live provider or Telnyx work.
