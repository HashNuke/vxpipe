# Goreman environment loading

- `bin/dev` added an unsupported `-env` flag whenever the root `.env` existed.
  Goreman 0.3.15 rejects that flag before starting any processes. Previous shell
  checks used a fake Goreman that recorded arguments without validating them.
- Inspected the installed binary's help and the
  [Goreman 0.3.15 source](https://github.com/mattn/goreman/blob/v0.3.15/main.go):
  Goreman changes to `-basedir` and loads `.env` automatically before starting
  processes. The existing base-directory argument already selects the right file.
- Removed the temporary environment integration test and its shell-suite
  invocation at the user's request. Keep the launcher fix and documentation.

## Verification

- An isolated launcher check failed with the user's exact `flag provided but not
  defined: -env` error. Removed the unsupported flag and kept Goreman's built-in
  environment loading. The check then passed with and without `.env`, using real
  Goreman and dummy processes from another directory. It did not read or print
  the user's environment file or start the full application.
- All five umbrella completion checks passed with `MIX_ENV=test`: formatting,
  compilation with warnings as errors, strict Credo, tests, and unused dependency
  checking. ExUnit reported 996 tests, zero failures, and 15 excluded tests.
- No UI or dependency changes were needed. The temporary check is not retained
  as a project test.
