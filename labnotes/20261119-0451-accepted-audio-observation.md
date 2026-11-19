# Accepted audio observation

- Continued from `23667dff` with a clean worktree. Inspection of STT capability
  admission showed observer attachment must bind to its current allocation and
  installed policy before automatic worker startup can safely use it.
- Added internal `attach_diagnostics/4` at that boundary. It requires ready native
  generation, installed policy, non-private allocation, exact track/source epoch,
  and a live capture handoff owned by this capability. Attachment does not change
  provider options, readiness, or speech control. Stale requests are rejected.
- Accepted PCM is offered only after the provider accepts input; denied, invalid
  and busy input never reaches the tap. Source mismatch retires the old tap while
  retaining the original provider result. Queue saturation drops diagnostics only.
- Handoffs optionally name a separate owning process (default remains receiver).
  Receipt/delivery checks require both processes alive, so capability death fences
  queued data without terminate cleanup. Successful policy installation closes the tap before acknowledgment; native
  retirement closes it before teardown. Rejected commands preserve observation.
- First four contract tests failed for missing attachment API; owner/death tests
  failed for missing owner option. Initial integration fixture needed explicit
  Enforcer installation: `initial_policy` controls demand but does not install
  live policy. Kept fail-closed attachment rather than allowing unknown policy.
- Idempotent reattachment regression then failed because it closed its own handle;
  exact repeats now preserve the binding, different bindings require fresh handles.
  Stale allocation requests leave the current binding intact.
- This supplies the real accepted-input hook, not automatic worker admission or
  an inference consumer. Opus/decoded-PCM capture, normalized sample mapping,
  operational reuse, automatic active-call subscriptions and persistence remain
  pending. No combined milestone C task is marked complete.

- Astra proved two further lifecycle regressions: prepared replacement state
  inherited the active tap, so discard cleanup revoked it; rejected policy
  commands revoked before validation. The latter also exposed comparing global
  revision to per-source STT interval. Retained both reproductions plus a duplicate
  revision case. Own malformed-metadata regression proved a missing source_epoch
  could crash otherwise accepted input. All four were red before fixes in
  `/tmp/vxpipe-audio-tap-review-red.log`.
- Prepared states now start without a tap. Successful policy installation revokes
  before acknowledgment, and native retirement before teardown; rejected commands
  leave observation intact. Bindings use full policy revision. Missing observation
  metadata closes the tap without changing accepted provider input.
- Prior umbrella run completed with exactly one MCP startup-ack failure; every
  other app passed. Isolated MCP file passed3/0 at the same seed. This is not final
  green acceptance; a fresh current-source full run is needed after this checkpoint.

- Final affected suite99/0; root static checks and Lean verification pass. Astra
  xhigh re-review is clean:25focused tests and13additional transition probes pass,
  covering replacement, wrong owner, reused token, global-policy and settings
  revocation. No remaining scoped findings. Full umbrella verification is next.
