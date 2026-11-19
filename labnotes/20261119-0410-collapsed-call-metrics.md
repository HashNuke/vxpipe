# Collapsed call metrics

- User requests Storybook first: per-target metrics collapsed by default with
  median, average and total; expand/collapse controls; display ms/ch/reqs units.
- Inspected shared Metrics implementation and existing History/Workbench stories.
  The linked production page requires sign-in in this browser; no production
  data was copied. Preview uses twelve explicitly synthetic turn measurements.
- Repeated series summarize separately by unit (normalizing only display aliases).
  Nulls are excluded with a visible recorded-value count; no all-null zero totals.
  Single measurements retain their source/context tooltip. Per-target controls
  and bulk expand/collapse preserve raw observation records and order.
- Added History → Metrics to the existing Storybook. The story opens Metrics
  directly; CallDetailsPage still defaults to Conversation in normal use.
- Four focused contract tests were red, then green. Updated the existing repeated
  observations test to expand before asserting individual preserved values.
  Shared React suite 49/0; affected Console tests 10/0; both typechecks and affected
  Console lint pass. Full Console frontend suite passed 1169/0 (149 files).
- Storybook initially served its old optimized workspace package, despite a fresh
  package build. Restarted the existing preview on6007 after clearing only its
  generated dependency cache. The first stale capture is not UI acceptance.
- Bounded Chrome pass on current build:1440x1000 dark/light and390x844 dark;
  collapsed defaults, per-target expansion, bulk controls, Enter/Space operation,
  compact units. Horizontal table scrolling stays inside its container; no page
  overflow. Temporary captures: vxpipe-metrics-collapsed-{desktop,mobile,light}.png.
- Passive capture admission changes remain separate and uncommitted. Its reviewer
  found delayed-publication grant resurrection and malformed-frame validation
  failures; those still require retained regressions/fixes after this UI request.
  No production deployment is part of this Storybook-first preview.

- Final GPT-6 Astra xhigh review returned no issues: independently verified 13
  focused tests, TypeScript, desktop dark/light and mobile rendering, contained
  scrolling, and zero axe violations within the metrics surface.
- User requested Tailscale access. Enabled a tailnet-only TCP Serve proxy on port
  6007 to the existing localhost Storybook; verified HTTP 200 and rendered the
  Metrics story through the Tailscale address. Sent the direct link via pushnotify.
- Current workspace build/typecheck and React suite 49/0 pass. Root format,
  warnings-as-errors compilation, strict Credo and unused-dependency checks pass.
  A fresh full Console frontend rerun and umbrella suite are running; final
  milestone acceptance remains pending with the passive diagnostics work.
