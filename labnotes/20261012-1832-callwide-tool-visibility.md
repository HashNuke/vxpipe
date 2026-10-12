# Call-wide tool visibility

- Remove the per-agent tool visibility sections from Advanced, keeping the
  call-wide visibility selector and timing fields.
- Preserve existing tool_visibility_overrides in source when editing other
  settings. This changes the authoring controls, not the runtime contract.
- Red: focused test fails because per-tool comboboxes are still rendered. It also
  covers saved overrides (including prototype-shaped tool keys) surviving edits
  to the remaining call-wide control.
- Preserve the pending compact wait-sounds change in this checkout.
- Green: all 15 settings-panel tests pass; frontend TypeScript and lint pass.
- Checked the rendered Advanced panel in desktop and mobile Storybook: only the
  call-wide visibility selector and timing fields remain. The mobile fixture's
  existing timeout validation renders correctly.
- Umbrella verification passed: formatting, compilation with warnings as errors,
  strict Credo, all 3,572 tests (zero failures), and unused dependency check.
  No runtime speech transitions changed; Lean does not apply.
