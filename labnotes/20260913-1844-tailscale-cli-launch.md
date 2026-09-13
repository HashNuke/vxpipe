# Tailscale CLI launch

- The user reproduced the macOS Tailscale bundle-identifier crash when running
  `bin/dev --tailscale`. Its PATH entry is a symlink outside the app bundle.
  The same app executable succeeds when invoked at its physical bundle path.
- Resolve the selected CLI's symlink chain before status and certificate calls.
  Keep PATH selection and support relative links, chained links, and spaces.
- The earlier Astro verification also found that the app cannot write directly
  to the repository's TLS directory. Use Tailscale's documented stdout export
  for certificate material and let the shell write private temporary files.
  Preserve existing certificates and stop startup when provisioning fails.

## Verification

- The user started `bin/dev --tailscale` successfully with the launcher fix.
  Leave that running stack untouched.
- Removed the added regression cases at the user's request. Only adjusted the
  existing shell check's mock commands and certificate arguments to match stdout
  export; no new test cases remain.
- The existing shell check, shell syntax validation, and `git diff --check`
  passed after removing the new cases.
- The earlier umbrella checks passed against the unchanged application code.
  TypeScript checking and all 11 frontend tests also passed before the separate
  database and transfer-desk commits.
