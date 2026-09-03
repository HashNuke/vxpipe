# Watchman Goreman Reload

## Goal

Restart the umbrella's `vxpipe` Goreman process when Elixir project files
change, using Watchman without allowing persistent Watchman triggers to outlive
`bin/dev`.

## Baseline

- `Procfile` starts `vxpipe` directly with `mix run --no-halt`.
- `bin/dev` starts only `vxpipe`, `samples`, and conditionally `caddy`.
- Goreman 0.3.19 is installed locally; neither `watchman` nor
  `watchman-make` is installed in the current environment.
- The worktree already contains unrelated user changes, including `README.md`;
  edits for this task must remain narrow.

## Checkpoints

### Red: development-process contract

- Added `test/bin/dev_test.sh` to require explicit Watchman prerequisites,
  inclusion of a `reloader` Goreman process, and exact delegation of the
  restart helper to `goreman run restart vxpipe`.
- Confirmed the focused test failed because the original `bin/dev` accepted an
  environment without Watchman.

### Green: foreground Watchman reloader

- Added `reloader: bin/watch-vxpipe` to the Procfile and included it in the
  explicit process list used by `bin/dev`.
- Added `watchman` and `watchman-make` prerequisite checks.
- `bin/watch-vxpipe` runs `watchman-make` from the repository root and watches
  umbrella source, application and root Mix manifests, the lockfile, and
  runtime configuration. Tests remain excluded by the inclusion patterns.
- `bin/restart-vxpipe` delegates to Goreman's RPC client with
  `goreman run restart vxpipe`.
- Used `watchman-make` rather than a saved Watchman trigger so the subscriber is
  a foreground Goreman child and cannot continue firing after `bin/dev` exits.
- Added `.watchmanconfig` ignores for build products, dependencies, frontend
  dependencies, and other generated directories to reduce Watchman crawl and
  event load.
- The focused shell test passed after the implementation.

## Research and decisions

- Current `watchman-make` source obtains an initial Watchman clock before it
  subscribes, so existing files do not cause an immediate restart at startup.
- Its `--run` action is synchronous and its default 200 ms settling window
  batches related writes. That fits the short-lived Goreman RPC helper.
- A saved Watchman trigger was rejected because its lifecycle and output belong
  to the per-user Watchman daemon rather than the foreground development stack.
- Wrapping `mix run --no-halt` directly was rejected because `watchman-make`
  waits for each invoked command to finish; a never-ending command would prevent
  subsequent reloads.

## Verification

- `test/bin/dev_test.sh` — passed.
- `bash -n bin/dev bin/watch-vxpipe bin/restart-vxpipe test/bin/dev_test.sh` —
  passed.
- `jq empty .watchmanconfig` — passed.
- `goreman ... check` — valid Procfile with `caddy`, `reloader`, `samples`, and
  `vxpipe`.
- `mix format --check-formatted` — passed.
- `mix compile --warnings-as-errors` — passed.
- `mix test` — passed, 6 call-engine tests and 13 gateway tests.
- `mix deps.unlock --check-unused` — passed.

## Limitation

- An end-to-end filesystem-event run was not performed because Watchman and
  `watchman-make` are not installed in the current environment. The focused
  test uses executable fakes at the process boundaries, and the command-line
  contract was checked against the current upstream `watchman-make` source.
