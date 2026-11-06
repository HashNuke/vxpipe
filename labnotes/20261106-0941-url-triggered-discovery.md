# URL-triggered discovery

- Scope: Storybook UI only, confirmed by the user. Preserved earlier uncommitted authentication-selector work; no commits created.
- Ran bin/setup successfully. Initial test-file write used a root-relative path from the assets directory and failed without changing files; corrected the path before the red run.
- Red: three focused discovery tests failed on the old selector and missing URL-driven states; cancellation test already passed. Green: all four passed after implementation.
- Added a separate red test for manual endpoint URL validation after removing the configuration mode. It passed after validating entered OAuth URLs directly.
- Local hook simulates resource discovery then OAuth metadata, debounces input, cancels timers on URL changes/close, preserves manual edits during discovery, and clears settings/credentials on URL changes. Synthetic endpoints derive from the entered origin for visibly distinct results, never from network requests.
- Kept the internal auto sentinel for an unresolved method; it is rendered only as a disabled Select authentication type placeholder. Anonymous access requires an explicit selection or the anonymous fixture outcome.
- Removed endpointMode and its dropdown. Existing manually configured stories retain their selected method until their URL changes.
- Focused suite: 95 MCP story tests passed. Console TypeScript check passed.
- Browser: desktop 1280x1000 and mobile 390x844 show populated editable endpoints with a fixed, reachable footer and scrollable content. Failure/retry inspected at both sizes; retry starts the progress state without losing the URL.
- Full Console frontend suite: 120 files, 922 tests passed. Focused ESLint passed. Formatting, warnings-as-errors compilation and strict Credo passed; umbrella mix test still running. git diff --check passed.
- Follow-up: user reported the empty Additional parameters section for Custom headers. Added a focused test, confirmed it failed on the visible empty disclosure, then hid the disclosure for that method.
- Follow-up green: all 96 MCP story tests and TypeScript passed. Rendered Custom headers at desktop/mobile; only the editable header rows and Add/Remove controls remain, with no empty disclosure.
- Completion: full umbrella mix test passed with zero failures in every application; Gateway took 377.6 seconds and Call Engine 170 seconds. The chained unused-dependency check also passed (exit 0). All required root checks complete. No backend code or dependencies changed.
- Final git diff --check passed; pre-existing changes and labnotes remain unstaged and intact.
