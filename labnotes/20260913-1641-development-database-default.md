# Development database default

- Local development should use PostgreSQL without requiring a database URL.
  Added `postgres://localhost/vxpipe_dev` as the Repo default in `config/dev.exs`.
  Runtime configuration uses it when `VXPIPE_DATABASE_URL` is absent or blank;
  an explicit URL still wins. Test and production do not inherit this default.
- Kept environment reads in `config/runtime.exs`. Persistence, managed admission,
  the caller sample, and the transfer sample all use the same effective URL.
- Removed the redundant URL entry added to the ignored `.env` during the previous
  transfer-desk investigation. Other local settings were preserved.
- Updated the development and Elixir setup guides, database operations guide,
  sample walkthroughs, and `.env.example` to explain the local database and its
  migrations. Revised the pending transfer error change so it no longer tells
  developers that a database URL is mandatory.

## Verification

- Before the configuration change, an isolated application check with the database
  URL explicitly unset failed because transfer admission returned 404. This is the
  externally visible failure the default must fix.
- Configuration checks passed for an unset URL, a blank URL, an explicit override,
  and test/production isolation. The configuration change uses a manual startup
  check rather than adding tests that merely repeat static configuration values.
- Updated the existing transfer error test first and confirmed its failure on the
  obsolete URL instruction. Both transfer tests and TypeScript checks then passed.
- The first startup check collided with Phoenix's recompilation after changing
  configuration. Its temporary script also changed compile-time `code_reloader`
  configuration. Removed that temporary override and recompiled the Console using
  its normal development configuration before retrying.
- The isolated application check then passed with the URL explicitly unset:
  transfer admission returned 409 before caller preparation; caller admission,
  caller session claim, and transfer admission returned 201 for the same call.
- Started the complete `bin/dev` stack with the URL unset and local provider
  fixtures. `/healthz` and `/transfer` returned 200; `/sample/transfers` returned
  `sample_call_not_prepared` (409), confirming that the sample was enabled.
- Headless Chrome inspection at 1280 by 900 and 390 by 844 verified the revised
  disabled-sample message using a simulated 404 response. Text wraps correctly
  and the retry button remains available. Closed the browser and stopped only
  the development stack started for this verification.
- Frontend verification passed: TypeScript and all 11 component/unit tests.
- Umbrella verification passed: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix test --max-cases 1` (996 tests, zero failures, 15 excluded, seed 586184),
  and `mix deps.unlock --check-unused`. Retained the serial suite invocation
  because prior default-concurrency runs had unrelated timing failures.
- `git diff --check` passed. No dependencies or lockfiles changed.
