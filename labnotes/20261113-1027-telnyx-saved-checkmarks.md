# Telnyx saved-key checkmarks

- Replace the visible Saved label after each masked key with the existing
  Lucide Check icon, using the shared success color. Both API and public keys
  keep their saved-state accessible labels; decorative dots are hidden from
  screen readers. Missing/unconfigured values retain their existing behavior.
- This is a presentation-only change in the shared production/Storybook dialog;
  no new behavioral tests were added. The six existing dialog tests pass.
- TypeScript, changed-file ESLint, formatting, warnings-as-errors compilation,
  strict Credo, unused-dependency checks, and diff whitespace checks pass.
- Inspected the inherited-credentials story in headless Chrome using
  agent-browser at 1440x900 and 390x844. Both dots/check pairs stay on one line,
  render in the success color, and retain field-specific accessible labels.
  No full suite or environment-file reads.
