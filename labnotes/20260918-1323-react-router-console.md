# React Router Console

## Goal

Replace production pathname parsing and direct history management with the latest React Router while preserving all Console URLs and request-lifecycle behavior.

## Research

- The npm latest tag resolved to `react-router` 8.4.0 on 2026-09-18.
- Version 8.4 requires Node >=22.22.0 and React/ReactDOM >=19.2.7.
- Declarative mode fits the Phoenix-owned build/server boundary; framework mode does not.

## Red-green evidence

- Added an unknown-admin-route test. It failed because the custom parser rendered tenants without canonicalizing `/admin/not-a-real-page`.
- Added React Router routes and a wildcard `<Navigate replace>` fallback. The focused app suite then passed 26 tests.
- Changed the sample route expectations to `/samples/pipecat-console` and
  `/samples/transfer`. Before implementation, the endpoint tests received 404
  and the playground rendered the caller page at the transfer URL. After adding
  the Phoenix scope and React Router basename, 18 focused endpoint/diagnostics
  tests and 8 focused playground/transfer tests passed.

## Implementation notes

- Renamed the production operator component from `AdminApp` to `App`.
- Renamed the older voice sample component to `PlaygroundApp`.
- Replaced the operator pathname regexes, `popstate` listener, and direct history writes with `BrowserRouter`, `Routes`, `Route`, `Navigate`, route params, search params, and `useNavigate`.
- Mounted the playground router at `/samples`, with explicit `/pipecat-console`
  and `/transfer` child routes. Phoenix serves only the resulting
  `/samples/pipecat-console` and `/samples/transfer` URLs; the former root-level
  routes return 404.
- Kept Storybook hash routing unchanged by request.
- Preserved abort controllers and `routeRef` stale-response checks across route transitions.

## Verification

- Focused `App` and `PlaygroundApp` suites: 32 tests passed.
- Console TypeScript check passed.
- Console ESLint passed.
- Rendered Chromium loaded both `/samples` pages. The transfer page linked back
  to `/samples/pipecat-console`, and neither the 1440 px nor 390 px inspection
  showed horizontal overflow. The Console root linked to both relocated pages.
- Root frontend type/build checks and 40 tests passed. Console type checking,
  ESLint, and 133 tests passed. The static Storybook production build passed.
- Root formatting, warnings-as-errors compilation, strict Credo, and unused
  dependency checking passed. The full umbrella test run reached the end with
  one intermittent Gateway failure; `mix test --failed` reran that exact test
  successfully (1 test, 0 failures). The route-focused Console checks remained
  green independently.
