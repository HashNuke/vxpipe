# Call model defaults

## Scope and decisions

- Follow-up to the Call settings and variable-editor changes. The user requested
  removing Output speech to text from the UI and grouping model defaults by role.
- The user chose to show both AI model paths together, then specified the group
  names **AI agents** and **Human participants**.
- Call settings now labels its first tab **Models**. The AI group contains
  **LLM + Text-to-Speech** and **Speech-to-Speech**. The human group contains only
  **Speech to text**. Existing provider/model/voice controls are reused.
- This is an editor organization change. Source capability inheritance and each
  agent's model-type selection are unchanged. The internal `defaults` tab ID is
  retained so existing issue routing continues to work.
- Output STT controls are hidden; existing source values remain intact, including
  when another default is edited. Runtime and compiler fallback support remains.

## Implementation and verification

- Red: three focused tests failed because the AI/human groups and Models tab did
  not exist. Green: all 9 focused tests passed after the UI change.
- The preservation test now verifies an existing output-STT value survives a
  text-to-speech default edit. Participant overrides and incoming-call source also
  remain intact.
- Fixed a TypeScript optional-field access in the new assertion.
- The first full frontend run exposed an asynchronous route-test race: it checked
  the URL immediately after the save notice, before navigation completed. The
  assertion now waits for the observable URL change. No route behavior changed.
- Full Console frontend suite: **70 files, 544 tests passed**. TypeScript and
  ESLint passed. `git diff --check` passed.
- Root formatting, compilation with warnings as errors, strict Credo, and unused
  dependency checks passed. Root test suite was started; result recorded below.
- Headless Chrome inspection via agent-browser: dark desktop at 1440×1000 and
  light mobile at 390×844, plus the actual editor page. Both AI paths are visible;
  the human group is separate; no Output speech to text control is rendered.
  Choosing Deepgram for human STT selects its recommended Flux model. No page-level
  horizontal overflow at either viewport. Browser session closed after inspection.
- Impeccable review: existing compact theme, shallow borders, and two-column model
  rows are preserved. Role groups have clear headings; AI model paths use named
  fieldsets. No new layout or interaction defect found in the bounded review.
- The Impeccable hook reported a stale design sidecar. Refreshed its navigation
  description from the existing DESIGN.md and generation timestamp, retaining the
  established tokens, components, and DESIGN.md itself.
- Temporary screenshots: `vxpipe-model-defaults-desktop.png`,
  `vxpipe-model-defaults-mobile.png`, `vxpipe-model-defaults-page.png`.
- Temporary logs: `vxpipe-model-defaults-{red,green,assets-tests,mix-test}.log`.
- Existing unrelated worktree changes were preserved. No commit created.

## Root test result

- The complete umbrella run finished: **3,465 tests, 7 failures**. Six failures
  are in the call-engine acoustic-inference/activity/Silero tests, and one is in
  Console's ElevenLabs configured-room speech-readiness test. The native Ortex
  library fails to load with `mis-aligned LINKEDIT string pool`; these are the
  same environment failures recorded in the preceding checkpoint. The previous
  transient STS transcript test failure did not recur in this run.
- Gateway: 595 tests passed. Calls, MCP, providers, agent runtime, artifacts, and
  persistence suites also passed. No Elixir, provider, or speech-state code was
  changed for this follow-up, so the Lean lane was not applicable.

## Commit checkpoint

- At the user's request, collected the interdependent editor changes with their
  source-contract checks, tests, documentation, and labnotes. Storybook navigation
  and tooling changes have separate commits.
- Pre-commit verification after the later model-field spacing refinement:
  **544 frontend tests passed**, TypeScript and ESLint passed, and the Storybook
  production build passed with its existing bundle-size warning.
- Removed machine-specific absolute paths from review metadata and temporary
  evidence references before staging. Generated documentation-site files and the
  empty default-agent-mode draft are excluded.
- A separate default-agent-mode implementation began while staging. Its new
  selector, tests, and module are left in the working tree; the index retains the
  completed two-path layout and the two defaults-panel tests from the green run.
