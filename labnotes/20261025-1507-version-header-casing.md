# Version header casing

- User requested canonical `X-VxPipe-Version` spelling and case-insensitive
  handling. Updated the preview request builder and API/Storybook documentation.
- The simulated directory previously indexed a plain object by one exact name.
  It now reads through standard HTTP `Headers` lookup. No production directory
  endpoint or networking was added.
- Added a focused boundary test for canonical, lowercase and uppercase field
  names, asserting version-filtered results and totals. All three cases failed
  first at the old exact-key lookup, then passed after the change.
- Pagination/search/header tests: 10 passed. TypeScript and ESLint passed.
- The API handoff explicitly requires case-insensitive names for reads, cache
  identity and CORS, while retaining the original version value.
- Headless Chrome smoke inspection confirmed Calendar still renders and global
  Google search returns AI Studio, Calendar, Docs and Sheets after the header
  change. Closed only the task browser; Storybook remains running on port 6006.
- All repository completion checks passed: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, and
  `mix deps.unlock --check-unused`. The full umbrella run took about ten minutes,
  chiefly in the existing call-engine and gateway suites; no failures occurred.
- Existing worktree changes preserved; no staging or commits.
