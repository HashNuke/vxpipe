# Service picker feedback

## Requests and decisions

- Show a centered prompt below the service dropdown before a selection.
- Replace unsupported credential-test prose with a red exclamation on Test credentials and the tooltip “Credential testing is unavailable for this provider.”
- Replace credential-issue text on service cards with an error icon in the same position as the connected checkmark. Keep explanations available on hover and keyboard focus.
- Use the existing shadcn tooltip component. Unavailable tests use aria-disabled and a guarded handler, so users can focus the button to learn why testing is unavailable. Saving remains available.
- Handle both known unsupported providers and an unsupported response from the credential-test endpoint.

## Evidence

- Red: the new picker test failed because the placeholder was absent; three unsupported-provider tests failed on the old disabled button; the override-card test failed because the labeled icon was absent.
- Green: 51 tests across OnboardingStory, ScopedServicesStory and ServiceCredentialForm; typecheck and ESLint passed.
- Chrome Storybook inspection at 1440×1000 and 390×844: empty picker, selected Cartesia, test tooltip, and tenant override error card. Clearing selection restores the prompt. Browser inspection caught the tooltip underneath the modal; a scoped tooltip layer now places it above the overlay.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency checks passed. Full suite: 3,790 tests, one failure in the unchanged speech-to-speech output STT lifecycle test (recognizer killed during a call). All 29 tests in that file passed unchanged on isolated rerun. All 303 Console backend tests passed.
