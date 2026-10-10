# Model field spacing

## Scope and changes

- Refine spacing and hierarchy in the existing AI agents and Human participants
  model groups. Preserve their grouping, provider/model rows and selection behavior.
- Group headings use 16px, model headings 14px, and shared Provider/Model/Voice
  labels 12px muted text. Previously the field labels were larger than the model
  headings. Keep labels 6px from their controls, capability headings 12px from
  their fields, rows 16px apart and model sections 24px apart.
- Use grid gaps for shared capability fields, keeping a dynamically shown Voice
  field with its Text-to-Speech provider/model row. The same shared treatment
  reaches AI and human participant inspectors. Other editor field styles are
  unchanged.
- Preserve the existing dirty worktree, including the newer model-default and
  variable-editor changes. Keep Storybook on 6006; no commits requested.

## Verification

- CSS/class changes only: no new tests. Existing defaults, capability, agent and
  human inspector suites pass: 37 tests across four files. Typecheck, lint and
  Storybook production build pass.
- Root format, compile with warnings as errors, strict Credo and unused dependency
  checks pass. The required umbrella run again failed on packaged acoustic
  inference because the local Ortex NIF cannot load (mis-aligned LINKEDIT string
  pool). Stopped after confirming the known environment failure.
- Chrome inspection covers the actual default editor page in dark desktop
  (1440px) and light mobile (390px), with Cartesia TTS showing its Voice input and
  Deepgram selected for human transcription. Computed label sizes and gaps match
  the intended hierarchy; Provider and Model stay aligned.
- Browser clicks on offscreen mobile controls initially dismissed the sheet;
  explicitly scrolled the Human participants group into view before verifying it.
