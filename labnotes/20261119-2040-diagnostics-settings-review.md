# Diagnostics settings review states

## Changes

Added Installation Storybook states for a concurrent settings conflict, a pending
save, and the current production saved-only response. The saved-only fixture omits
`collection_status` on both read and save, so the control reports unavailable
rather than inventing a distributed applied acknowledgement. Existing applying/
applied stories remain explicit simulated examples.

The conflict fixture advances the saved revision as another operator, rejects the
stale save and requires reload before retry. Subsequent writes validate the loaded
revision. The journey's optional diagnostics scenario and Storybook render key
keep scenario state isolated. This changes fixtures only, not production settings
authority, operational VAD, provider behavior or the settings control itself.

## Verification

- Two focused fixture behavior tests failed before implementation (missing conflict
  and saved-only outcomes); the existing twelve tests passed.
- Focused settings-control and Installation page tests: 18/18 pass. Independent
  Astra xhigh review reran the same selection, also 18/18, and is clean.
- Console settings endpoint plus existing diagnostics LiveView selection: 19/19
  pass. The settings endpoint cases prove admin/superadmin saves survive a fresh
  GET, stale revisions conflict, custom/member/anonymous/bearer access is denied,
  and Installation URL access remains separate. The unrelated LiveView cases are
  regression evidence only, not production settings UI acceptance.
- TypeScript check and targeted ESLint pass. Root format, warnings-as-errors
  compile, strict Credo and unused-lock checks pass. The focused Impeccable source
  detector reported no findings in the fixture and Installation stories.
- No full suite or live provider test ran. No deployment or service restart.

## Bounded rendered Chrome inspection

Used agent-browser/headless Chrome with desktop 1440×1000 and mobile 390×844:

- Admin desktop dark: Diagnostics visible, Installation URL controls absent.
- Saved-only desktop light: off/on via keyboard Space; saved value updates while
  collection status stays unavailable. Checkbox retains keyboard focus and a
  visible outline.
- Conflict mobile dark: stale-save alert, disabled checkbox and visible reload
  action. Keyboard Enter reloads the other operator's enabled value; Space can
  then save off. The applied result here is a fixture acknowledgement only.
- Pending-save mobile dark: disabled control retains the last confirmed value
  while the saving message remains visible.
- Save-failure Superadmin desktop dark: error/reload shown; separate URL controls
  remain visible. No horizontal overflow in the inspected states.
- Member-denied mobile over the Tailscale Storybook address: access-unavailable
  message, no benchmark checkbox. This is simulated role presentation, not the
  server authorization proof above.

Screenshots were inspected locally under `/tmp/vxpipe-settings-*.png`; no personal
or production call data was used. The independent reviewer inspected saved-only,
conflict and pending captures. There was no visual defect requiring a second
polish pass or styling changes.

The UI milestone task stays open: Storybook resets on full-page reload and cannot
prove browser persistence against a real backend. Backend GET persistence and
rendered fixture behavior are distinct evidence. Production end-to-end reload,
distributed effective status and live installation demonstrations remain open.
