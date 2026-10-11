# Portable design hooks

- The pending Impeccable hook update used machine-specific paths, which the
  repository's commit rules prohibit. Keep the new binary launcher but resolve
  it through `HOME` on POSIX and `USERPROFILE` on Windows.
- Preserve the conditional no-op when the skill is not installed, existing
  event matchers, timeouts, and status messages.
- Verification: JSON parsing and POSIX `sh -n` passed. Windows command structure
  retains the prior conditional pattern; Windows execution was not available.
- Related review metadata and temporary-evidence references were made portable
  in their owning editor checkpoint. Generated site artifacts and an empty draft
  labnote remain uncommitted.
