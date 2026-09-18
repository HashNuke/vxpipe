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
- Added reusable provider service marks for the admin inventory (Google, Zenmux, Deepgram, Telnyx,
  and Twilio) with compact responsive tiles and provider-specific color treatments. Desktop and
  mobile Storybook review show the marks improving scanability without introducing page overflow;
  the focused admin test and TypeScript check pass.
- Replaced the hand-drawn Google/Zenmux approximations with direct tree-shaken `@lobehub/icons`
  components. The logo resolver now uses an explicit per-provider source map, with LobeHub
  components where selected, official vendored assets where selected, and local avatar-like
  provider marks as the fallback. The LobeHub dependency is owned by `@vxpipe/console-assets`;
  assets tests and the root Storybook production build pass.
- Google is configured to use Google's official full-color G mark, ZenMux to use LobeHub, Telnyx
  to use its official media-kit logo, and Deepgram/Twilio to use local avatars. The Google and
  Telnyx assets are vendored directly under `src/admin/assets/icons/`, with provenance recorded in
  the directory README. The component falls back locally if an imported image fails to load.
  Rendered Storybook confirms the Google and Telnyx marks use their official vendored assets.
- Added Vertex AI as a distinct service provider rather than treating it as Google. Its separate
  service row, credential-provider option, API response parser allowlist, and icon asset are now
  covered by the focused admin test and rendered Storybook review. Replaced the initial external
  Vertex AI SVG with the current official Google Cloud asset from `core-products-icons.zip`.
- Restored a useful Credentials column with server-provided masked previews: partially revealed
  values show exactly four mask characters plus the final four characters, while fully hidden
  values show exactly six mask characters. Added per-row edit actions that open the existing
  credential modal with secret fields blank.
