# Opt-in Tailscale

- The user requested plain `bin/dev` without a Tailscale dependency and Tailscale
  only when `--tailscale` is passed. The user further clarified that neither
  `--http` nor `--https` should remain. Default to HTTP and accept only the
  `--tailscale` option.
- Validate arguments before any Tailscale discovery or certificate provisioning.
  Keep the existing Astro process integration and other uncommitted work.
- Update the development guide with the default localhost Console URL and the
  explicit Tailscale launch command.
- Changed the shell test first to run plain `bin/dev` with neither Tailscale nor
  jq on its PATH, assert HTTP mode, and exercise the existing TLS contract through
  `--tailscale`. Added dependency and invalid-argument checks. The red run failed
  on the former default's Tailscale requirement, as expected.
- After the clarification, the focused red check confirmed that the retained
  `--http` alias was still accepted. Removed it and updated usage to
  `bin/dev [--tailscale]`.

## Verification

- `bash test/bin/dev_test.sh` passed. The default launch delegates all three
  processes to Goreman with HTTP selected and neither Tailscale nor jq available.
  The opt-in path checks its dependencies and passes the existing discovery,
  certificate, TLS environment, and process-selection assertions. Both removed
  flags and extra arguments are rejected before Tailscale work.
- Shell syntax validation and `git diff --check` passed. Updated current launch
  instructions; historical milestone verification records retain their original
  commands as evidence of the checks performed then.
- All five umbrella completion checks passed with `MIX_ENV=test`: formatting,
  compilation with warnings as errors, strict Credo, tests, and unused dependency
  checking. ExUnit reported 996 tests, zero failures, and 15 excluded tests.
- This changes launcher behavior only; no UI files changed or live Tailscale
  certificate requests were needed. The existing Astro integration remains intact.
