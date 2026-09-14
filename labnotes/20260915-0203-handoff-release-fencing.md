# Handoff release fencing

## Reproduction

The previous goal turn committed b14d556: policy revisions after adoption reconcile before any
media release. Revalidated the current worktree; only another agent's site/visual-note changes
are present. All five gates last passed 1,368 tests; intermittent recovery acceptance remains open.

The release worker currently verifies only the attempt identity after connection release calls.
A policy revision or resource generation change during those acknowledgements can therefore
publish success against stale readiness. Add owning engine cases that open the caller output but
withhold its acknowledgement, then change policy, renew the connection generation, or return a
release error. Each must close without transfer success, activation, recovery or redial. The
output fixture gains only an opt-in deferred release acknowledgement; ordinary output behavior
is unchanged.


## Red/green and design decisions

- Initial red: 3 engine cases, 2 failures (`vxpipe-release-fencing-red.log`). Policy and
  generation changes publish completion instead of closing; an explicit release error already
  closes correctly. Green after validating the saved post-adoption inventory and running the
  existing exact-resource `Probe.verify/2` after release acknowledgements (3 cases pass).
- Check policy/bindings before and after that bounded probe. A pending, failed or changed resource
  cannot be silently recollected as a new success. This path never retries, promotes participants,
  changes the policy, restarts providers, or extends the attempt deadline.
- Native policy acceptance includes two changes during the Gateway release request. The existing
  one-use OTP debug callback now selects adoption or release. Gateway has already released output
  when it awaits that request, so these cases exercise uncertain partial admission. Both the room
  and media connections terminate without a `transfer.active` message. All nine native policy
  cases pass (`vxpipe-release-fencing-native.log`), including earlier successful retries and audio.
- A second red exposes policy revision after the worker verifies release but before RoomAuthority
  publishes completion (`vxpipe-release-completion-red.log`). The coordinator must compare current
  room bindings and validate the saved policy candidate before finalizing. Resource/provider probes
  stay in the worker; no network preparation is added to the authority callback.
- An attempted extra connection at this last boundary was rejected by the existing transfer
  admission guard, so it did not reproduce a stale binding. Removed that invalid test setup; do
  not treat its rejection as evidence for general changing-listener acceptance. No admission
  rule was relaxed to construct the test.
- Generalized the existing test telemetry pause to select prepare/release completion. No production
  test hook or new process is introduced. The coordinator shares its existing fail-closed path.


## Validation in progress

The four final engine failure cases and the complete focused human/agent/inventory lane pass:
65 tests, zero failures (`vxpipe-release-fencing-focused.log`). All five root checks are running
with seed 235296 and concurrency four. No development server restart, browser work or UI changes.
The milestone keeps its existing open recovery and broader failure/privacy acceptance tasks; these
specific fences do not establish all changing-listener or partial-release behavior.


## Design review

Keep this as a completion fence around existing release operations. Reuse the current readiness
probe and authoritative room inventory instead of introducing another revision counter, resource
owner, or preparation phase. Retrying after a release acknowledgement can conceal uncertain media
admission, so only the established before-release path may reconcile and retry. The coordinator
checks its own current binding and the policy candidate; it does not perform provider readiness
calls. The existing phase deadline and fail-closed room lifecycle remain authoritative.

## Final verification

All five root gates pass on the final code: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict`,
`mix test --max-cases 4 --seed 235296`, and `mix deps.unlock --check-unused`.
The umbrella run has 1,374 tests, zero failures and 15 exclusions
(`vxpipe-release-fencing-gates-*`). Counts: MCP 37, agent runtime 91, engine 632, Calls 81,
Gateway 371, artifacts 19, persistence 49 and Console 94. It includes all 39 native startup/
transfer cases and the existing phone harnesses. No additional code/test edits followed this run.

Documentation links and diff whitespace checks pass. Keep the 24 remaining milestone tasks open:
this checkpoint establishes the specified release/completion fences, while recovery intermittency,
other failure stages and complete changing-listener acceptance still need evidence. The prior
intermittent recovery failure did not occur in this run; no causal fix is claimed. Commit exact
checkpoint paths and preserve the other agent's site and visual-note work.
