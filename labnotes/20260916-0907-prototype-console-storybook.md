# Prototype console Storybook

## Scope and decisions

Build the requested interactive Node/Storybook prototype. The user changed the earlier local
source-boundary plan to npm packages within the repo and explicitly named them `@vxpipe/core`
and `@vxpipe/react`, at `packages/core` and `packages/react`. Keep both private during prototyping.
The root npm workspace does not absorb the existing Phoenix assets or documentation site.

Inherit DESIGN.md Operator's Bench and the concrete layout from the console/onboarding plan.
This is a code prototype of that composition, with fixture-backed states, not a new visual-world
selection or a production call integration. No platform/provider credentials or microphone access.
Core owns framework-neutral public contracts; React consumes those public contracts. Story fixtures
and app-specific Getting Started composition live outside package exports. Logs contain RTVI only.

## Tooling and evidence

Checked official Storybook React/Vite and TypeScript docs and npm package metadata. Storybook
10.6 supports React 19 and Vite 7. Use the current local Node runtime (25.9) and document Node
22.12+ for workspace commands. Storybook is local development tooling, not another production
frontend server. Reuse existing test libraries and TypeScript major versions.

## Verification progress

- Initial worktree clean except the empty labnote created for this task before the user's naming
  correction. No earlier changes discarded.
- Focused interaction tests written before implementation: denied mic + typed input, leave preserves
  history, RTVI filtering/details, and honest missing-alignment state.
- An initial test command ran before npm installation finished and could not find Vitest; this is
  tooling setup, not the expected red result. Wait for install and rerun before implementation.

## Implementation and review

- Added private root npm workspaces, Core contracts, reusable React views, and a synthetic
  Storybook host. Builds emit ESM/declarations; styles are scoped. Neither reusable package
  imports Phoenix, application routes, or a protocol SDK. No publishing or live media integration.
- Initial interaction and setup tests failed on the missing modules before implementation.
  The focused component checks then passed. Removed the removal-only ready-state test when
  the user clarified that deleted UI should not get tests.
- Followed user refinements: dark default; Storybook-native preview controls; removed the
  console title, prototype notice, tenant/protocol/revision labels, session divider and footer.
  Ready has no placeholder participants and says “No call active.”
- Call actions now occupy the top-right row; microphone/input and speaker/output groups sit
  below. Each has an accessible icon toggle and a bordered native selector. On mobile the
  device groups stack. Message headers use name, flexible space, sequential bouncing dots,
  then timestamp; reduced motion disables the bounce.
- Finish reviewer found populated metrics before a call, all example buttons starting the same
  fixture, and a Unicode arrow used as an icon. Ready metrics are now unavailable, example
  selection survives Start, and the arrow uses authored SVG geometry. Agent/human selection
  regressions failed before the fix and passed after it. Setup progress also failed at 3/4
  before replacing the fixed count with its actual state.
- The fresh finish reviewer returned `ship` after reading all eight refreshed captures and
  source. Its three material findings are resolved; this approves the synthetic prototype,
  not production call-flow acceptance. Existing type-ramp/corner findings were corrected;
  no new detector suppressions were added and no unresolved detector findings remain.
- Shadcn registry feasibility was checked against its official registry, Select and monorepo
  documentation. A later focused checkpoint replaced the native device selectors with the
  exported shadcn-style Select primitive backed by Radix UI; its own labnote records the red/green
  behavior and rendered verification. The package is still not a published shadcn registry.
  Keep Core independent and derive npm/registry UI from one source.

## Verification evidence

- `npm test`: 9 tests passed. `npm run check`: both package builds and strict TypeScript pass.
  `npm run build-storybook`: static build passed, with the usual large-chunk advisory only.
- Rendered headless Chrome inspection via agent-browser: dark desktop 1440px, mobile 360px,
  metrics 768px, Ready, RTVI Logs, light theme, incomplete setup desktop and complete setup
  mobile. Page width matches all three viewports. Captures are ignored local review artifacts.
- Browser interactions confirmed microphone/speaker toggles, both device selections, typed
  sending, RTVI event filtering/inspection and paused feed. Prototype events and form values
  remain local synthetic data. Browser animation inspection reported three running animations
  at 0/0.16/0.32s delays; reduced-motion emulation reported no animation for all three dots.
- Umbrella format, warnings-as-errors compilation, strict Credo and unused-lock check passed.
  The first plain umbrella test attempt hit six native audio/gateway failures and stalled;
  it was stopped without changing backend code. Reused the repository's previously documented
  bounded command: `mix test --preload-modules --max-requires 1 --max-cases 4 --seed 235296`.
  That complete run passed: 1,622 tests, zero failures, 39 integration exclusions across eight
  applications. This is a passing bounded run, not a claim that the initial concurrency failures
  were diagnosed or repaired by the frontend work.
- Native file watching served stale source during iteration. Enabled Vite polling for this
  development host and excluded build artifacts; no runtime server configuration changed.

Production console, platform bootstrap and Getting Started milestone gates remain unchecked.
This checkpoint supplies the requested UI prototype and package boundaries only.

The focused surface brief records the built layout without rewriting global DESIGN.md.
The additional separate-session browser launch check was stopped when the agent-browser daemon
became unresponsive; example selection is covered by the passing component tests, and no live
human-acceptance verification is claimed. The completed layout and device checks used the main
Chrome session. Both inspection sessions were closed; Storybook remains running for the user.
