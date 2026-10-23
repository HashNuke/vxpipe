# Align media controls

## Request and decision

- Put the four Media labels and dropdowns on the same row on desktop for both participant and entry cards.
- Reuse the existing responsive inline field layout in their shared `MediaPolicyFields` component, with a consistent label width and vertically centered controls. Narrow viewports retain stacked fields.
- Keep routing help below each row and preserve expanded routing controls, call-wide settings, and policy behavior.
- This is a presentation-only change; use existing media behavior tests and rendered browser inspection rather than adding tests of CSS class names.

## Verification

- Before editing, inspected the desktop agent Media story: all four labels occupied separate rows above their dropdowns.
- Confirmed agent, human participant, and entry inspectors use the same media fields component.
- Headless Chrome inspection through `agent-browser`: agent and outgoing entry Media tabs at 1440 × 1000; entry at 390 × 844; human participant with restricted transcript routing at both sizes, including the light theme. Desktop labels share a 144 px column, all four selects share the same left edge, and measured label/control vertical centers match exactly. Mobile fields stack with no horizontal overflow; routing details remain readable in the scrollable panel.
- Existing settings-panel, agent-inspector, and human-inspector tests: 3 files, 48 tests passed, including media policy edits and read-only behavior.
- TypeScript, ESLint, production CSS build, format check, compilation with warnings as errors, strict Credo, unused dependency-lock check, and `git diff --check` passed.
- Retained the complete umbrella test evidence from the immediately preceding checkpoint (3,811 reported tests, zero failures, 134 excluded); this change only adds layout props and does not change backend or policy logic.
- Impeccable layout scan reported no findings before or after the change. No suppressions or additional visual changes were needed.
