# Metrics row alignment

- User clarified expanded target labels must stay at the top; expand controls
  belong on the right so labels align with rows lacking a control. STT represents
  one session row per participant and must not expand into per-turn observations.
- Applied top alignment only to body row headers, moved controls after labels with
  space-between layout, and excluded STT/Agent STT from expandable targets. Raw
  STT observations remain available to median/average/total summaries; two STT
  participants retain two distinct row headers and aggregate independently.
- Added a two-participant regression, confirmed failing against the previous
  Metrics implementation before passing the update. Storybook now includes two
  STT participants and repeated LLM/TTS measurements. Shared React suite50/0,
  package build and Console typecheck pass.
- Chrome inspection at1440x1000 and390x844: expanded labels remain12px from row
  top; buttons are right of labels; two STT rows remain80.5px high while twelve-turn
  LLM/TTS rows expand to769px. No page overflow on mobile. Checked collapsed and
  expanded states. Captures under /tmp/vxpipe-metrics-layout-*.png.
- Restarted Storybook after rebuilding the shared package and clearing its generated
  optimized-dependency cache. Temporarily stopped/re-enabled the Tailscale TCP
  proxy because its listener prevented Storybook's port availability check.
  Preview is again reachable on100.65.185.95:6007.
- Existing Cartesia test correction and latency-diagnostics work remain separate.
- Astra xhigh review clean, independently confirming desktop/mobile geometry,
  two summarized STT rows and expanded LLM/TTS. Workspace/Console typechecks,
  affected Console lint and CallDetailsPage tests4/0 pass, alongside React50/0.
  Root static gates pass. The separate broader diagnostics run remains failed;
  its fixture-ordering repairs are tracked independently, not hidden by UI checks.
