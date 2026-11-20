# Configured call settings

## Migration

The configured integration fixture now supplies the persisted DB snapshot loader
at call startup. Removed SettingsSupervisor/Reader/Projection setup and live
revision polling. The user-approved contract is immutable per call: enabled calls
continue collecting, disabled calls stay off, later calls observe DB updates.

The four existing operational-VAD × collection matrix cases now update the real
settings store, send unchanged provider PCM and complete a model response on the
existing call, and verify its original settings revision. Source replacement
retains that call's original choice. After teardown, a new configured call proves
the opposite choice and new revision. No classifier/provider bypass was added.

Removed the obsolete active-call settings-outage/recovery tests. Kept twenty
configured lifecycle cycles and optional RSS measurement, now checking two turns
share one run until call teardown. Queue saturation still proves bounded counts,
bytes, loss and cleanup. Inference failures retire at call teardown rather than a
global toggle. Writer-failure, routing, barge-in and egress acceptance remain.

## Verification

This is migration to the independently red-green-tested backend contract, not a
production behavior implementation. Focused configured verification is pending
the shared Mix lane. No live provider, native performance run, full suite or
commit. No prohibited environment file was accessed.

Focused verification complete: the four real-DB choice/source-replacement cases
passed, then the combined 19-case selection passed with seed 640743: four snapshot
cases, eight count/byte saturation cases, two twenty-call lifecycle cycles, four
inference crash/hang cases and the cross-human configured barge-in case. Removed
macro-constant conditional warnings before the final run. Logs:
vxpipe-configured-settings-matrix.log and vxpipe-configured-settings-focused.log.
Scoped formatting and git diff --check pass. All sessions are terminal; shared
Mix lane released. No production code changed by this migration.

At the parent's request, rebuilt current production assets with `mix assets.build`
(TypeScript/CSS/esbuild pass), then ran the two production settings browser tests:
2/2 pass, seed 664632. Inspected the rendered superadmin desktop and admin mobile
normal/conflict screenshots. The existing checkbox label remains unchanged;
obsolete global collection status is absent, mobile content fits, and the conflict
reload control remains visible. Screenshots:
/tmp/vxpipe-diagnostic-settings-6820-desktop.png,
/tmp/vxpipe-diagnostic-settings-3235-mobile.png and
/tmp/vxpipe-diagnostic-settings-3235-conflict.png.
Logs: vxpipe-call-settings-assets.log and vxpipe-call-settings-browser.log.
All build/test/browser processes are terminal; no live provider request occurred.
