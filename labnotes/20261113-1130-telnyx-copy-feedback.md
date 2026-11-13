# Telnyx modal feedback

- Removed the redundant success paragraph below the webhook URL. Copy success
  stays in the button for two seconds, then returns to Copy. Repeated clicks
  restart the timer; unmount clears it. Copy failures retain manual-copy guidance.
- Distinguished field labels (13px, medium, primary text), hints (12px, regular,
  muted), and application scope (11px badge). The same component and stylesheet
  serve the application and Storybook.
- Red: the existing copy interaction test failed because the success paragraph
  was still present. Green: all 19 focused scoped-services and Telnyx dialog
  tests pass; TypeScript and focused ESLint pass.
- Rendered the shared Storybook modal in headless Chrome at 1440x900 and
  390x844. Verified hierarchy, tenant override, and no horizontal overflow.
  Native clipboard permission was denied in the browser session; used a local
  clipboard stub to inspect success timing. The real failure path remained
  usable. Screenshots stay outside the repository.
- No live telephony tests or provider requests were made for this UI change.
