# Operator login challenge and admin dashboard

## Goal

Plan the trusted operator login flow and installation-wide React admin dashboard before changing
runtime behavior.

## Progress

- Added a milestone split into independently committable checkpoints.
- Required all admin pages to move from small component stories to complete Storybook pages before
  production route integration.
- Kept the login and code-entry flow server-rendered in Phoenix; every `/admin` page is React.
- Confirmed from the current persistence model that calls identify a definition revision, allowing
  definition-scoped call queries without adding a second mutable definition association.

## Decisions

- One installation-wide operator authority sees all tenants; this milestone has no users or RBAC.
- `mix vxpipe.login` issues a 10-minute challenge with five attempts and an eight-digit code.
- A successful exchange creates a 12-hour non-sliding operator session.
- Platform and tenant API keys remain programmatic credentials and are not UI login credentials.
- Admin-specific React code stays in Console assets; reusable call components remain in
  `@vxpipe/react` and call state remains in `@vxpipe/core`.
- The admin UI uses shadcn-compatible source components and the established debug-console design.

## Verification

- Independent GPT 6 Astra xhigh review found the first draft needed a token-free auth destination,
  HTTPS outside loopback, an explicit Calls-owned operator authority and a complete legacy
  route/session cutover. Those findings were incorporated.
- Re-review cleared the specification with no remaining blocking findings and confirmed the nine
  checkpoints are bounded and Storybook precedes every production page integration.
- The milestone index contains 30 ordered entries and the declared 22-complete/8-incomplete count.
- Local Markdown links resolve and `git diff --check` passes.
- No runtime code, schema or generated artifact changed; no runtime test was applicable.
