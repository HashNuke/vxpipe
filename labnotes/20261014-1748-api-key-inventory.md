# API key inventory details

## Requests and implementation

- Add a Type column using the existing permission-kind labels: Create & Join Calls and Full Access.
- Add a Created column using relative times, including “few seconds ago” for newly created keys, and a shadcn tooltip containing the exact UTC date/time. Timestamps are focusable for keyboard users.
- Add a back link on its own row above the creation heading, returning to the inventory without creating a key. Disable it during submission, matching Cancel.
- Extend the UI key contract with createdAt and populate the Storybook/navigation creation fixtures. The existing-key story now demonstrates both access kinds. This UI surface still uses the existing fixture-backed key flow; this change does not add a persistence/API integration.
- Retain the established horizontally scrollable table on small screens; set a minimum table width to prevent access labels and names breaking into fragments.

## Verification

- Red: two focused tests failed on the missing Type column and back button.
- Green: 36 tests across ApiKeysSetupPage, OnboardingStory and AdminJourneyStory. Typecheck and ESLint passed.
- Chrome inspection at 1440×1000 and 390×844: inventory, UTC timestamp tooltip, create form and back navigation. Corrected cramped mobile table columns after the first visual pass; horizontal scrolling keeps all four columns readable.
- Follow-up alignment review: the inline arrow offset the heading from the form. Moved “← API Keys” to its own row; heading and form labels now align on desktop and mobile.
- Follow-up tenant context: the navigation journey already showed tenant names, while the shared standalone setup-story layout omitted them. Added the existing navigation-context styling inside the main content for tenant pages only. Red: two new story tests failed without the tenant name. Green: all 46 focused tests passed; typecheck and ESLint passed.
- Root checks passed: format, warnings-as-errors compilation, strict Credo, all 3,790 backend tests and unused-dependency check.
