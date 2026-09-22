# Integrate STS tools

- Applied the isolated `49213160..e839119d` tool delta on top of the committed
  peer-close checkpoint. Keep Google response-ownership research/controller reds
  separate. The three worker checkpoints are supervised lifecycle `96fb0395`,
  crash-report privacy `1e1ac9f2`, and original admission deadline `e839119d`.
- Main reviewed the tree/bridge/room dispatch, owning compiled-room tests and
  deadline/privacy runtime deltas. Independent xhigh review cleared the lifecycle
  scope except the reproduced late-start race and separately cleared privacy.
  Independent follow-up of the committed deadline repair remains pending.
- The review reproduction is retained in worker labnotes and regressions:
  suspend the invocation supervisor after submission enters preparation, await
  public unavailable, resume, and require no worker execution/record/child.
  A worker-side absolute deadline also fences delayed begin commands. Accepted
  execution keeps the original five-second budget and honest unknown outcome.
- This integration retains private completion leases; it does not implement the
  running acknowledgement/private continuation commit protocol or close full
  STS tool acceptance. No hosted/native/load run is authorized by this checkpoint.
- Independent xhigh review cleared `e839119d`: original deadline is preserved
  through both preparation and queued begin, cleanup leaves no accepted record,
  and accepted-work behavior is unchanged. Review was source-only.
- Parent integration handle `12739` exited 0: **102 tests, zero failures**, seed
  0, two schedulers, 16.0 seconds. Log `vxpipe-sts-tool-parent-integration.log`;
  exact seven-file command is in the worker admission-deadline labnote. The
  injected termination reports contain redacted reason/message/state as expected.
- Synchronized `docs/speech-provider-contract.md` with these implemented host
  ownership/deadline/privacy guarantees and explicit still-open conversation
  semantics, after recording that integration task in the milestone. Reproduction
  methods remain committed with the regressions for later development cycles.
