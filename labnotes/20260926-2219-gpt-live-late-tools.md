# GPT-Live late tools

Date: 2026-09-26. Starting revision: `1baf3af8`.

## Work and decisions

- Plan audit: Package 8 explicitly requires in-flight delegated work from a
  lost socket to finish and reach the new session as context. The adapter
  previously reset `GPTLiveDelegation`, so an already-running room invocation
  returned `{:error, :stale_request}`. A fake-socket capability test confirmed
  that red failure.
- Captured only still-pending call references and tool names at reseed. Results
  become private `session.thinking.append` commands, queued until replacement
  readiness. Existing function-call output is never replayed on the new
  Responses delegation. The published speech history remains untouched.
- Split JSON results into bounded context commands because one thinking
  command accepts at most 2,000 bytes. A duplicate result remains stale.
- The focused decision record is `docs/gpt-live-reseed-tool-results.md`.

## Verification

- The red capability test failed with `{:error, :stale_request}` and passed
  after implementation.
- Fake-socket capability, delegation and session tests: 39 tests, zero
  failures. Format, warnings-as-errors compile, strict Credo (1,135 files,
  zero issues), unused dependency, and Lean verification checks passed.
- The umbrella suite passed 2,853 tests, zero failures and 59 tagged
  exclusions. CallEngine passed 1,662 tests and Gateway passed 519 tests.
