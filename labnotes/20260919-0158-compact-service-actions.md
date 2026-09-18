# Compact service actions

- Removed redundant “Tenant service” text from connected service cards. Inherited,
  override and disabled labels retain their existing meaning; subsequent review also
  removed “Platform service”.
- Replaced visible Connected text with a green double-check icon (accessible Connected
  text retained), immediately followed by a pencil button at the top right. The button
  retains its provider-specific accessible Manage name and opens the existing modal.
- Removed the footer Manage button; capability tags now use the full card width.
  Missing Telnyx public-key status is now a yellow warning icon inside the Telephony
  capability badge, with hover and screen-reader text. Both copies of a connected Telnyx
  service now show the same double-check icon; capability readiness is represented by
  the warning rather than inconsistent connection status.
- Chrome screenshots inspected at 1440x1000 and 390x844: compact-actions-desktop.png and
  compact-actions-mobile.png under ignored tmp/onboarding-storybook. No layout overflow.
- 29 existing onboarding/scoped-service tests, TypeScript, ESLint, format, compilation,
  strict Credo, unused-dependency and diff checks pass. Layout detector returned no findings.
- The umbrella run completed during this review: 1724 tests, two failures in existing
  participant shutdown and room-audio-egress tests. Both affected files pass independently
  (3 and 8 tests). Backend remains unchanged; details are in the preceding modal labnote.
- Existing worktree changes preserved. No commits or application-server management.

- Final warning placement checked on desktop/mobile in the Telnyx AI-only story, including
  both copies of the card. Pencil click opens the Telnyx form. The initial browser batch
  used an unsupported nth-selector syntax and stalled; closing only our browser session
  and retrying with a section-scoped CSS selector succeeded. No application issue found.
- Final 29 focused tests, TypeScript and lint pass after these follow-up refinements.
