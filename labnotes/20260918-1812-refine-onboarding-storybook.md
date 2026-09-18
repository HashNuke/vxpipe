# Refine onboarding Storybook

## Scope and design

- Approved flow: tenant service setup with provider credential modals and three
  capability indicators, followed by sample recipe cards. Cards remain readable
  but cannot run until their required capabilities are configured.
- Prototype the new flow, resumable tenant-directory entry points, provider/model
  choices, and failure states in Storybook before changing production routing.
- Use the tenant display name `Demo` and the user's exact readiness/setup copy.
  Change the default name for newly created demo tenants; do not rename existing
  tenants or alter their durable identity.
- Preserve the existing operator design tokens and use diagram-based recipe art.
  Google and Zenmux cover LLM in current Vxpipe integrations; Deepgram covers
  STT/TTS. Telephony remains optional for these browser samples.
- The user manages `bin/dev`; Storybook is owned by this task.

## Verification

- Added behavioral tests before implementation for modal focus, capability
  coverage, blocked recipes, explicit model choice, tenant-specific resumption,
  and the new demo tenant default name. The initial five Storybook tests failed
  against the previous flow. Two additional return-navigation/provider-choice
  regressions failed before their fixes; a final ready-tenant navigation test
  failed because the directory returned to services instead of samples.
- The eight focused Storybook tests now pass. Console frontend type checking,
  ESLint and all 141 tests in 25 files pass after the final navigation correction.
- Calls' two demo-setup tests: red on `DemoTenant` versus `Demo`, then green
  (seed 781917). Console onboarding endpoint tests: 3 passed (seed 154176).
- Static Storybook build passes. Vite retains its large-chunk advisory for the
  shared Storybook iframe; no build errors or dependency changes.
- Chrome inspected 1440, 768, 390 and 360 px layouts. Reviewed dark/light service
  setup and recipes, validation failure, tenant directory/nudge, recipe preview,
  Deepgram and Twilio modals. Dummy credential submission filled STT/TTS together,
  then Google unlocked all three recipe actions. Tab/Shift-Tab wrap within the
  dialog, Escape closes it, and input receives initial focus. The Narrow story
  creates a 390 px iframe on desktop. The 360 px Twilio dialog fits without
  horizontal overflow. Screenshots are local ignored artifacts under
  `tmp/onboarding-storybook/`.
- Rendered review found a broad SVG rectangle selector overwriting the nested
  agent icon. Restricted it to direct child rectangles and confirmed the fix in
  light desktop and blocked tablet recipe layouts. All deterministic design-hook
  findings were fixed (type ramp and neutral overlay/shadow colors); none remain
  suppressed or unresolved. Existing design-sidecar drift was not modified.
- Root formatting, warnings-as-errors compilation, strict Credo and unused-lock
  checks pass. The full umbrella run encountered billing/audio readiness timeouts;
  all affected files pass unchanged in owning-child reruns with the same seed
  (403084): 7 billing tests and 22 audio tests. The completed full run reports
  1,724 tests, 7 timeout failures and 39 excluded. A final root
  `mix test --failed --seed 403084` reruns all seven failures: 2 Calls tests and
  5 Gateway tests, all passing. No timeout increases or unrelated backend edits
  were made. This is a full run plus successful retries, not a clean first pass.

## Implementation and operational notes

- Split the prototype into focused service coverage, provider modal, recipe card,
  recipe diagram, samples page and tenant-directory components. Shared credential
  form additions have backward-compatible defaults.
- Story state retains per-tenant connections and sample/provider choices during
  navigation, without retaining credential input. Refresh resets fixtures. The
  static validation/loading scenarios intentionally hold their illustrated state.
- The versioned JSON provider catalog mirrors existing sample defaults; it is
  prototype data, not a new server model-selection or credential authority.
- The user-facing flow and production follow-up boundaries are recorded in
  `docs/tenant-setup-experience.md`; milestone notes explicitly leave durable
  integration and root-home/demo-mode acceptance unchecked.
- Storybook initially held an old story index after new exports. Restarting with
  Chokidar polling refreshed discovery. Broad polling also consumed substantial
  CPU while the umbrella/native-audio suite and frontend builds ran. The first
  umbrella timeouts occurred during that overlap. This is a suspected source of
  contention, not yet a proven diagnosis. Closed the QA browser and stopped the
  task-owned Storybook process before retrying; `bin/dev` was not touched.
- Storybook did not exit promptly on SIGTERM, and early replacement attempts
  failed with EADDRINUSE. Confirmed ownership via port 6006, terminated the stuck
  task-owned process, and kept the failed-start logs in ignored temporary output.
- Restored Storybook with the normal `npm run storybook -- --ci` command, without
  broad Chokidar polling. Confirmed all 23 onboarding entries on port 6006. The
  existing Vite polling configuration is unchanged. Storybook remains running
  for user review; the task's named browser session is closed.
- Final diff inspection and documentation-link checks pass. No commits, database
  edits, production onboarding route replacement or live-provider calls were made.

## Follow-up: shared onboarding for new tenants

- The user requested name-only tenant creation on the directory, followed by the
  same service setup for every tenant. Added a focused creation dialog and four
  stories (27 total), keeping telephony optional for WebRTC callers.
- Two new behavior tests failed first because the directory had no New tenant
  action. All ten focused tests now pass: creation trims the name, blocks blank
  names, shows pending state, opens empty services, and preserves independent
  tenant progress when returning through the directory. Type checking and ESLint
  pass. The final Console suite passes all 143 tests, and the Storybook build passes.
- Rendered the name-only creation dialog at desktop width, submitted a dummy
  tenant and verified its empty service page. Inspected the light-theme creation
  error on mobile and retried successfully with the retained name. Reviewed the
  updated directory with the newly created tenant. No design-hook findings remain.
- This follow-up changes frontend prototype files only. It makes no further
  changes to the backend verified by the full umbrella run and failed-test retry.
  Rechecked root formatting, compilation, Credo and unused dependencies after the
  frontend follow-up; all pass.
