# Merge main updates

## Context and resolution

- Committed the approved Media simplification as `08f0b817`, then attempted the requested push to `origin/main`.
- The remote had advanced by 119 commits to `d93a692a`; merged those commits without rewriting either history.
- Resolved the editor API test conflict by retaining the upstream canonical provider-path assertion and the local tool-catalog lookup assertion together. The automatically merged API client retains the browser-only editor-lookups endpoint and uses the upstream canonical endpoints for shared operations.
- Resolved the lockfile conflict by keeping the upstream `partitioned_buffer` dependency alongside the already-approved Phoenix 1.8.16 upgrade. ReqLLM 1.29.0 and the upstream OAuth dependencies remain present; dependency resolution succeeded.
- Upstream also supplies the save/unload-guard synchronization fix for the intermittent failure observed during the previous checkpoint.

## Verification

- All 102 frontend test files and 792 tests passed after the merge, along with TypeScript, ESLint, and the CSS build.
- Root format check, compilation with warnings as errors, strict Credo, and unused dependency-lock check passed. Only third-party dependency deprecation warnings appeared during their first compilation.
- Attempted the Lean verification lane because upstream includes speech lifecycle changes; it could not start because `lake` is not installed. This is an environment limitation, not a failing model or conformance result. Its temporary database was removed.
- The complete root umbrella suite passed after the merge: 4,444 reported tests, zero failures, 156 excluded. Its task-owned temporary database was removed successfully.
