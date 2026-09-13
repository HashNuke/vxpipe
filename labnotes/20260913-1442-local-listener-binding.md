# Local listener binding

- The HTTP endpoint failed with `:eaddrnotavail` because `APP_HOST` from `.env`
  resolved to a Tailscale-range address absent from the machine's active network
  interfaces. Checked only the relevant setting and reported derived booleans;
  no environment-file contents or hostname were printed.
- Runtime configuration resolves `APP_HOST` to the Console's HTTP bind address.
  Normal `bin/dev` selected HTTP but left the hostname to inherited environment
  and dotenv configuration, retaining an old Tailscale listener target.
- The user clarified that localhost should be the fallback when `APP_HOST` is
  unset, then removed their setting. Keep explicit `APP_HOST` values respected
  and change the runtime HTTP fallback from `0.0.0.0` to `127.0.0.1`. The Console
  URL already defaults to localhost. The existing `--tailscale` branch still
  sets the discovered hostname and Tailscale address.
- Update development instructions to describe the fallback and the requirement
  that an explicitly configured bind address be available locally. No edits to
  the user's `.env` or new environment integration tests are needed. Verify the
  configuration change through actual stack startup and existing checks.

## Verification

- Confirmed `APP_HOST` was absent from both the tool environment and `.env`
  after the user's edit. Started plain `bin/dev` with no hostname override.
  The actual Console endpoint bound to `127.0.0.1:4000`.
- Console `/healthz`, Console `/`, and Astro `/docs/en/` all returned HTTP 200.
  Opened the Console and docs in headless Chrome through `agent-browser` and
  inspected screenshots of both pages. No application errors were displayed.
- Closed the verification browser and stopped the full stack with Ctrl-C.
  Goreman terminated all three processes and exited successfully.
- The existing shell integration suite and shell syntax validation passed.
- Formatting, compilation with warnings as errors, strict Credo, and unused
  dependency checking passed with `MIX_ENV=test`.
- The first full suite after the fallback change reported one call-engine test
  failure; the other seven applications passed. The captured output did not
  include that failure's details, and `mix test --failed --trace` from the
  call-engine directory found no stored failures.
- A full rerun with seed 36728 reported a refresh timeout in
  `CatalogRefresherTest` and an unavailable result applying mixer policy in
  `RoomMixerTest`. These use 1,000 ms and 100 ms operation deadlines respectively.
  Both files passed together in isolation: 16 tests, zero failures, same seed.
  The runtime configuration change is in the development-only branch. No
  unrelated call-engine code or tests were changed.
- The full suite passed with `MIX_ENV=test mix test --max-cases 1 --seed 36728`:
  996 tests, zero failures, and 15 excluded tests. The failures seen at default
  concurrency did not reproduce in the focused or serial runs; they remain a
  separate test-stability concern.
- Final diff review and `git diff --check` passed. After shutdown, no listeners
  remained on ports 4000, 4321, or Goreman's RPC port 8555.
