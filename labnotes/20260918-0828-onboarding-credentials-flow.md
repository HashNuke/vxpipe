## Checkpoint: Storybook onboarding flow

- Replaced the prototype's combined Deepgram/Google form with an explicit first-run sequence:
  auto-created `DemoTenant`, optional rename, service selection for STT/TTS/LLM/telephony,
  per-service credential fields, validation result, and sample-definition loading.
- The prototype models validation as a provider API-check boundary and exposes `Last validated just now`;
  it does not make real provider calls or persist secrets yet.
- The repository contains one checked-in call-definition fixture at `examples/call-definitions/development.json`.
  The UI therefore says one starter definition is included while retaining the three existing example-call
  experiences below the checklist.
- Red test added first in `packages/react/test/gettingStarted.test.tsx`; focused behavior now passes.
- `npm run build-storybook --workspace=@vxpipe/react` and `npm run build --workspace=@vxpipe/react` pass.
- Rendered Storybook review passed at 1440px and 390px. The mobile review caught and fixed a
  legacy label cascade that stacked service cards vertically; the final cards remain compact and
  horizontally composed. No page-level horizontal overflow was observed.
- Follow-up architectural correction: Storybook ownership is repository-wide, not React-package-only.
  The single root `.storybook/` config discovers both `packages/react/stories/` and
  `apps/vxpipe_console/assets/src/admin/` stories; package scripts point at that same config.
- The root toolchain now owns the Storybook/Vite/Tailwind/font dev dependencies. `npm run build-storybook`
  from the repository root passes and emits `storybook-static/`; the root dev server exposes the same
  onboarding story at the shared Storybook URL.
- Simplified the admin service inventory by removing service-type/status fields and provider-specific
  descriptive labels from the table model/UI. The list now shows service name, credential state, and
  added/updated time.
- Added deterministic relative-time formatting (for example, `3 days ago`) while retaining the exact
  UTC ISO timestamp in the `time` element and hover title. The focused formatter test, console-assets
  test suite, TypeScript check, and rendered Storybook review pass.
