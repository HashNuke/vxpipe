# Diagnostics settings UI cleanup

The user chose database-persisted settings that apply only when a new call starts
and explicitly rejected new explanatory UI copy. Removed the obsolete applying/
applied/unavailable collection-status line, polling timers/budgets, status type
and Storybook propagation simulation. Kept the toggle label, saving confirmation,
conflict/reload, lost-response recovery, load errors and role behavior.

Removed tests for the retired propagation state machine and redundant saved-only
story. A focused test verifies ordinary persistence without background polling or
propagation text. Before implementation,
two relevant UI assertions failed; afterward all seven focused tests passed.
The Console TypeScript check and mechanical Impeccable detector pass.

Rendered Chrome verification used the existing Storybook on loopback 6008:
1440x1000 disabled and 390x844 enabled/saved + conflict states. Space toggles the
focused checkbox; conflict disables it and exposes Reload. No horizontal overflow,
no collection-status element and no added new-call explanatory label. Screenshots
are under /tmp/vxpipe-settings-cleanup-*.png. Browser session closed. Existing
production-page browser test now expects the obsolete status element to be absent;
its backend rerun passed both Admin/Superadmin cases after a fresh assets build
(seed 664632), with desktop/mobile normal and conflict screenshots inspected.

Independent Astra xhigh checkpoint review is clean. Backend call-start semantics
and configured DB transitions pass their focused suites in this same checkpoint.
