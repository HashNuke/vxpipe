# Add section actions

- Added persistent Connect a service buttons alongside AI providers and Telephony headings. Retained the last-position add card in each grid.
- Mobile follow-up: hide the heading action while that section has no saved services. Show it once a service is present; empty-state add cards stay available.
- Red/green: four focused assertions failed for the missing heading actions, then all 17 tests passed. Full console suite: 150 tests pass; TypeScript, lint, Storybook build, and diff whitespace checks pass.
- Headless Chrome verified desktop buttons and mobile empty/AI-connected/both-connected states at 1440px and 390px, including connecting Telnyx via the add card. Computed visibility confirmed both heading buttons hidden when empty and only AI visible when just AI services exist. Screenshots: ignored tmp/onboarding-storybook/section-actions-*.png.
- Browser click initially did not open the modal; retried the known card via DOM click, then used the dropdown and normal form actions successfully.
- Follow-up connected-card work reused the section-actions browser session and closed it on completion. Existing staged work preserved; Storybook remains running and bin/dev untouched.
- Backend check evidence remains in the preceding group-service-cards checkpoint; this follow-up changes only Storybook presentation and its existing modal entry points.
