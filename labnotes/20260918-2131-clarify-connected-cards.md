# Clarify connected cards

- Separated provider identity/Connected status from the Manage action. Cards now use an article with a compact identity row, explicit green Connected label, capability tags, and a standard outlined Manage button. Removed whole-card hover/click styling; the real button opens the existing credential modal.
- Kept invalid/unavailable credential messages and a Connect action for those states. Kept the three-column grids, last-position add cards, and responsive heading actions.
- Red: new focused test failed because the connected card had no separate article/status/action structure. Green: 18 onboarding tests pass, including Manage opening the existing modal.
- Full console suite: 151 tests pass. TypeScript, lint, Storybook build, and git diff --check pass. Existing build chunk-size advisories remain.
- Headless Chrome inspected desktop/mobile connected cards, dark/light styling, and Manage Deepgram opening the modal. Screenshots: ignored tmp/onboarding-storybook/connected-cards-*.png. Closed the section-actions browser session; left Storybook running.
- No backend changes or repeat of the previous checkpoint’s umbrella suite; scope was Storybook card presentation and its existing Manage action. No commits or staging changes.
