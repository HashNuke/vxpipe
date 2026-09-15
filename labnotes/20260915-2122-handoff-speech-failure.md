# Handoff speech failure

## Boundary and hypothesis

The combined tenant-opening umbrella reproduced missing failed progress during required
STT loss after policy adoption and before release acknowledgement. The policy authority
and RoomAuthority independently monitor that recognizer. The policy child is significant:
its exit can shut down the room before transfer cancellation emits progress/history.
The existing test permits a shutdown exit but still requires those terminal effects.

Add a deterministic ordering case alongside the existing partial-release matrix. Suspend
RoomAuthority, disconnect the real test speech transport, await the policy authority's
actual enforcer-failure exit, then resume. Keep the failed progress, bounded archive cause,
no recovery/activation and room teardown assertions unchanged. This checks project-owned
supervision and failure effects, not OTP monitor behavior.

## Red/green and design review

- Deterministic policy-first speech failure: **8 tests, 1 failure**, seed 235296. The new
  case missed failed progress; all seven existing release invalidations passed.
- Added direct policy death during release: **9 tests, 2 failures**, same seed. Both new
  cases missed the required failed progress before any production change.
- RoomAuthority now monitors the policy child. That child no longer independently triggers
  incarnation auto-shutdown; RoomAuthority emits pending transfer progress/history and stops.
  Keep the policy process temporary, the remaining significant children and all deadlines.
- Preserve a failure already latched by handoff cancellation. Otherwise recognize the exact
  destination capability/ingress in a policy enforcer failure; direct policy loss uses the
  existing source-authority-changed cause. Owner shutdown disposes the transfer tree.
- Focused green: **10 tests, 0 failures, 57 excluded**, seed 235296, including all nine
  release invalidations and ordinary planned-room closure after policy loss.
- Design review: registration and monitor setup occur before entry startup. Loss during
  initialization still fails room startup; runtime policy loss has a single closure owner.
  No synchronous callback into RoomAuthority is introduced. Existing policy/enforcer APIs,
  privacy barriers, deadlines and other significant children retain their contracts.
  The focused decision document records alternatives and implications. Independent final
  implementation review remains open after the previously reported reviewer usage limit.

## Broader barrier result

The complete three-file group ran **92 tests, 1 failure**, seed 235296. A failed policy
commit now reaches the coordinator's existing `handoff_commit_failed` stop before the policy
monitor; the old case required the incidental supervisor `shutdown`. Its no-bridge/no-success
checks remained satisfied. Review of that synchronous error branch also found missing transfer
history. Strengthen the case with archive acceptance and the explicit commit-failure exit;
prove the missing history red before adding the record. This keeps both API-error and monitor
paths responsible for terminal effects before closure.

- The strengthened rejected-barrier case failed at its missing archive fact: **1 test,
  1 failure**, seed 235296. No progress or audio expectation was relaxed.
- Added a real policy exit while commit is blocked in a manual enforcer. Both commit
  failure cases are red (**2 tests, 2 failures**, same seed): authority exit bypassed failed
  progress through `GenServer.call`'s exit; rejection omitted the archive fact.
- The commit boundary now converts that exit to its existing bounded commit error. Its
  terminal handler records the missing failure fact before returning `handoff_commit_failed`.
  This closes the synchronous-request path as well as the policy-monitor path.

The two privacy-barrier cases are green (**2 tests, 0 failures, 39 excluded**, seed
235296). Formatting, warnings-as-errors compilation and strict Credo pass; the final
umbrella run is in progress. No browser change is part of this Engine checkpoint.

The final umbrella's Engine application passes **683 tests, 0 failures, 12 excluded**,
seed 235296. This includes the complete affected files and the earlier live-only STT
policy case. Gateway and the remaining applications are still running at this checkpoint.

## Final checkpoint evidence

All five umbrella gates pass on the combined checkpoint:

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix credo --strict`
- `mix test --preload-modules --max-requires 1 --max-cases 4 --seed 235296`
- `mix deps.unlock --check-unused`

The suite reports **1,510 tests, 0 failures, 30 excluded**, including **683 Engine tests**
and **413 Gateway tests**. The deterministic policy-first regression establishes the handoff
shutdown race and its fix. Native repeated-transfer audio also passes this run, but that does
not establish a cause or fix for the earlier Morse timing failure. Preserve that distinction.
All checks are terminal; logs are `tmp/handoff-policy-final-*.log`.

The changed documentation links resolve and `git diff --check` passes. This is a separate
usable failure-handling checkpoint after `daec74b`; tenant transfer credential acceptance and
the remaining credential milestone checkpoints are still open. Final independent review remains
unavailable after the previously reported reviewer usage limit; no independent approval is claimed.
