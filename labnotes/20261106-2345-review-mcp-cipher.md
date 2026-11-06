# Review MCP cipher

- Scope: the MCP secret-envelope adapter and focused tests. Reuse the existing
  installation keyring; do not introduce a separate key-management system.
  Record stores, authorization, management APIs and OAuth lifecycle are later
  checkpoints. Original cipher implementation had three failing missing-module
  tests before the adapter was added, then all three passed.
- Independent GPT-6 Astra xhigh source review found no blocking encryption or
  identity-isolation defect. Added its suggested regressions for project-owned
  key-ID binding, provider/MCP namespace separation, exact byte limits, envelope
  version/size rejection and redacted JSON-encoding failure.
- These additions strengthen evidence for existing behavior; no runtime code
  changes were needed. All seven focused tests and all 467 Persistence tests pass.
  Format, warnings-as-errors compile, strict Credo and unused-dependency checks
  pass. Exact independent staged review precedes commit.
- Staged review strengthened the oversized-envelope assertion: an unavailable
  keyring must still yield unreadable for oversized data, proving rejection
  happens before key lookup rather than merely failing the altered GCM tag.
