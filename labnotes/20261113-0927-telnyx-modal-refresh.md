# Telnyx modal refresh

## Scope and direction

- Refresh the shared Storybook Telnyx connection dialog within the existing Console visual system (Operate mode).
- Two independent sections: credentials and Voice API application, each showing its effective source and a tenant override action. The application defaults to a platform value. The webhook lives in the Voice application section; either tenant override selects the tenant URL.
- Use calm section dividers, aligned values, existing Inter/Geist Mono and theme tokens, inline override editing, and a fixed dialog footer. Remove the localhost preview notice.
- Keep fixture saves, restore defaults and Cancel coherent. Production routing is outside this design checkpoint: persistence currently resolves Telnyx ingress by application ID and enforces its uniqueness. Sharing applications in production needs number-to-call-spec/tenant resolution first.

## Evidence

- Inspected the existing story in headless Chrome with agent-browser.
- Initial bin/setup was blocked because local PostgreSQL was stopped; started the installed Postgres app and reran setup successfully.

## Implementation and verification

- Added a dedicated Telnyx preview dialog, leaving other providers on the generic credential dialog. Platform and tenant fixtures retain independent application values. Added application-only and credentials-only override stories.
- Either credential or application override selects the tenant webhook immediately. The platform webhook returns only when both settings inherit platform defaults. Save commits the preview changes; Cancel discards them.
- Red: seven focused cases failed on the absent independent controls, read-only inherited application and platform application field. Green: 53 tests across ScopedServicesStory, OnboardingStory and mcpStories/McpServicesStory passed.
- Root and Console TypeScript checks and changed-file ESLint passed. A frontend test attempt overlapped the root workspace build's clean step and could not resolve @vxpipe/react; rerunning after the build completed passed all 53 cases.
- bin/setup succeeded after starting PostgreSQL. Mix formatting, warnings-as-errors compilation, strict Credo and unused-dependency checks passed. The full umbrella suite completed with one MCP caller-cancellation acknowledgement timeout; all other suites passed. `mix test --failed` then passed that one test (0 failures) without code changes.
- Browser inspection covered inherited settings, application-only override, credential editing, 1440px desktop, 1280×720 short desktop, 390×844 mobile, and light/dark themes. No page overflow at the short desktop; the footer stays inside the dialog. Adjusted content padding and read-only input specificity after the first inspection round.
- Captures are under the ignored .impeccable/review/telnyx-refresh/ directory. The first image wait expression did not survive CLI batch parsing; used an expression without embedded quotes and confirmed images loaded for the final captures.
- The targeted Impeccable detector reported no findings. Independent finish review returned **ship**, with no material fixes, for all six supplied captures and the scoped implementation.

- Browser interactions confirmed an application-only save survives reopening, and an ID containing spaces leaves the dialog open with an associated invalid field and validation message.
- The documenter compared the implementation and six captures with PRODUCT.md and DESIGN.md: no durable system change or documentation update needed. Pre-existing design-token documentation drift was left unchanged.

## Follow-up copy and action placement

- Removed the public-key explanation and its now-unused accessibility description reference at the user’s request. Helper text should only support a decision or action the operator needs.
- Moved the restore action into each section header. Override becomes Use platform default in the same position; credential fields expand underneath. Saved tenant credentials retain a compact Edit action alongside the restore button.
- Updated accessible action names and existing tests: four focused tests failed before the controls changed; all 37 scoped-services and onboarding tests then passed. Console TypeScript, changed-file ESLint and diff checks passed.
- Inspected editing and saved-override states at desktop and 390px mobile widths, and verified restoring credentials collapses the fields and restores the platform webhook. This follow-up changes copy and layout only.

## Voice application webhook follow-up

- Moved the webhook field into Voice application. Overriding the application selects the tenant webhook even when credentials are inherited; restoring either setting preserves the tenant URL while the other remains overridden.
- Removed the additional webhook-scope/update notice at the user’s request.
- Red: three focused tests failed on the old scope selection and missing webhook inside the Voice application region. Green: all 54 relevant frontend tests passed after updating the demo tenant-key fixture to the new alphanumeric format. Console TypeScript and changed-file ESLint passed.
- Browser inspection confirmed both URL states in desktop and mobile layouts, without horizontal page overflow. Final captures are the `voice-*` files in .impeccable/review/telnyx-refresh/. Fresh finish review returned **ship**, with no material fixes.
- Final umbrella formatting, warnings-as-errors compilation and strict Credo passed. The full suite had two unrelated failures (context-compactor acknowledgement timing and room registry cleanup); both passed on `mix test --failed` without code changes. The documenter confirmed that PRODUCT.md and DESIGN.md need no changes for this refinement.
- Final unused-dependency and diff checks passed.

## Local PostgreSQL setup follow-up

- At the user's request, disabled Postgres.app's “Ask for permission when apps connect without password” preference and restarted the running PostgreSQL 18 server after tests finished.
- Verified a passwordless localhost query succeeds, `shared_preload_libraries` no longer includes the permission-dialog hook, and `listen_addresses` remains `localhost`. This is a local application preference, with no repository database configuration change.

## Production follow-up

This checkpoint changes the Storybook configuration model only. Production still resolves scoped Telnyx events through a unique application binding (`TelephonyServiceStore.fetch_telnyx_application/2`). Supporting one platform application requires resolving the called number to its owning tenant and call spec, alongside the existing credential/signature scope. Do not treat the preview's routing explanation as verification of that backend behavior.
