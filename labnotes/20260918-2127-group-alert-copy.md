# Group alert copy

- Moved the existing service-setup and tenant-renaming description inside the tenant-created success alert, beneath its title. Kept the exact copy and aligned the check icon with the first line.
- Mechanical presentation change: no new runtime behavior or initial red test. Existing focused onboarding suite passes (17 tests); git diff --check passes.
- Inspected rendered Storybook in headless Chrome at 1440px and 390px. Both sentences are inside the bordered alert and wrap cleanly on mobile. Screenshots: ignored tmp/onboarding-storybook/alert-copy-desktop.png and alert-copy-mobile.png.
- Closed only the alert-copy browser session. Preserved existing staged/unstaged changes; no commits, server restarts, or backend changes. Broader checks from the immediately preceding checkpoint were not repeated for this markup/CSS regrouping.
