# Transfer desk connection

- Reproduced the reported failure against the running local server:
  `POST /sample/transfers` returned 404 with `sample_transfer_disabled`.
- `VXPIPE_DATABASE_URL` is unset. Runtime configuration only starts `SampleCall`
  and enables managed admission when that value is configured. The caller page
  has a database-free fallback; the transfer desk has no equivalent. The approved
  human-web-transfer milestone and existing walkthrough require PostgreSQL.
- The old message suggested requesting a transfer even when the entire sample
  backend was disabled. Handle that known state separately with the required
  database setup and restart instructions, and clarify the development guide.
- Applied the impeccable clarify workflow to the existing page without changing
  its layout or visual identity. Its context check reported stale design sidecar
  metadata; refreshing design metadata is outside this task.
- Added a focused component check first. It failed on the old disabled message,
  as expected. Keep the existing successful admission/acceptance test intact.
- PostgreSQL was already running locally. Created `vxpipe_dev`, applied all 11
  migrations, and added `VXPIPE_DATABASE_URL` to the ignored local `.env` while
  preserving its other settings. The running Goreman process needs a full
  `bin/dev` restart to load this setting; restarting its child alone does not
  reload `.env`.
- The initial migration attempt encountered concurrent development compilation
  and missing provider configuration in the shell. Using `--no-compile` with
  the existing local model fixture and Morse speech profile allowed database
  setup without loading or printing provider credentials.

## Verification

- The focused transfer component suite passed both tests after the change.
  `npm run check` and the complete frontend suite passed (11 tests).
- Headless Chrome inspection through agent-browser confirmed the setup error
  and retry button at 1280 by 900 and 390 by 844. The message wraps without
  clipping. Closed the inspection browser afterward.
- A separate process using the development database and local provider fixtures
  verified the real application endpoint: transfer admission returned 409 before
  a caller was prepared; caller admission, caller session claim, and transfer
  admission each returned 201, with both admissions targeting the same call.
  An initial check omitted the caller session claim and received 503; the proper
  sequence passed. No credentials or admission tokens were printed.
- The PostgreSQL check left the user's running development server intact. A live
  two-browser audio handoff was not exercised in this pass.
- Umbrella checks passed: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix test --max-cases 1` (seed 562159), and `mix deps.unlock --check-unused`.
  Used one concurrent test case because prior verification had exposed unrelated
  timing failures under the default concurrency; see the local-listener labnotes.
- `git diff --check` passed. No dependencies or lockfiles changed.
