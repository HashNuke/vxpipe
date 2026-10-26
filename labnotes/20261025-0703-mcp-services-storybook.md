# MCP services Storybook

## Scope and decisions

- User requested reviewable Storybooks only. Added an isolated prototype under
  `apps/vxpipe_console/assets/src/admin/mcpStories`; no backend, production-route,
  API, dependency or lockfile changes.
- Preserved existing Services/navigation/dialog primitives and Console tokens.
  Impeccable context was loaded once; this is an ordinary Operate extension.
- Tenant-only MCP inventory, searchable grouped picker, six presets and Custom
  MCP; no platform MCP inheritance. Tool allowances stay in agent settings.
- Explicit manual CIMD/DCR and custom authentication follow the user's latest
  request, superseding the earlier proposal to hide registration choices.
- Custom authentication covers bearer tokens, header credentials, Basic and
  configurable OAuth; advanced parameters are disclosed on demand. Anonymous
  access is explicit. No remote requests or real authorization are performed.
- Google Calendar, Sheets and Docs are separate official Developer Preview
  endpoints. Presets, primary sources and design decisions are recorded in
  `docs/development/mcp-services-storybook.md`.

## Implementation and verification

- Red: first six interaction contracts failed because the prototype component
  did not exist. Implemented the fixture workflow; all six passed.
- Added a seventh contract for signing-key masking before changing the control;
  confirmed failure (textarea lacked password masking), then made reveal explicit.
- Initial full frontend run hit the existing App.auth superadmin PATCH assertion;
  its isolated rerun also failed. No production/auth files were changed. The
  subsequent complete run passed all 824 tests across 106 files.
- TypeScript and ESLint pass. Source formatting used a transient formatter;
  package files and lockfiles are unchanged.
- Reused the existing agent-managed Storybook server on port 6006. Headless Chrome
  session `mcp-services-review`; no tmux or replacement server was started.
- Browser inspection: 1440×1000 and 390×844, dark/light picker, tenant inventory,
  custom form, OAuth advanced fields, CIMD/DCR, Google setup, error, reconnect,
  simulated authorization, success and empty state. Screenshot evidence is local
  under ignored `.impeccable/review/`.
- Fixed search input's duplicate border/focus ring in one correction batch.
  Mobile document width equals viewport width (390px), with dialog inside 8px
  margins. Escape closes the modal; inherited dialog handles focus containment.
- A browser batch waited on the wrong scenario title (custom rather than Cal.com);
  canceled only that inspection command and resumed with the observed title.
- Finish reviewer identified one material recovery issue: long auth forms could
  submit with the validation alert offscreen. Added an eighth red-first contract
  for error focus, then focus/reveal the alert after failed submission. Confirmed
  in Chrome at desktop/mobile widths; both captures show feedback above the
  footer. Reviewer scored the finding resolved and returned `ship` for that fix.
- Final frontend run passes 825 tests across 106 files; TypeScript, ESLint and
  static Storybook build pass. Build retains the existing large-chunk advisory.
- All required umbrella gates passed: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test` and
  `mix deps.unlock --check-unused`. The combined command exited zero. Final
  Persistence/Console summaries: 427/394 tests, zero failures (36/21 excluded).
- No design findings were suppressed. Existing font choices and unrelated
  research files were preserved. The review browser was closed; Storybook stays
  running on port 6006.
- Impeccable documenter confirmed the extension reuses existing primitives and
  tokens, and needs no PRODUCT/DESIGN changes. It noted pre-existing DESIGN.md
  drift for Settings navigation and dark panel lightness; left both untouched.

## Remaining implementation

This checkpoint deliberately does not implement OAuth/CIMD/DCR networking, token
storage or refresh, real tool discovery, service persistence or call-runtime
integration. The user will review this workflow before that work is authorized.
