# Room service cutover

## Scope and decisions

Compose the optional participant-input diagnostics subtree into planned rooms and
inject the Calls collector via SourcePort. Remove the old node-wide coordinator,
agent-owned source query and eligibility wrapper in the same checkpoint. Preserve
Engine-root admission capacity across Calls restarts. No provider configuration,
Telnyx code, live provider tests or deployment changes.

RoomAuthority lifecycle callbacks send asynchronous room-local reconciliation
hints. Snapshot reads and periodic retries remain authoritative; call callbacks do
not wait for diagnostics. Stops are left to existing room lifetime monitoring.

## Reproductions and changes

- Initial Calls composition and configured routing tests failed on the unsupported
  source-pool `port` option; composition is now migrated to SourcePort.
- Configured agent transfer closed the original capture/run although the STT
  ingress survived. Review traced this to `held_participant_ids` during asynchronous
  agent preparation: the candidate query excluded held sources and the service
  irreversibly closed capture. A focused query regression failed (6 tests, 1 failure).
  Candidates now preserve accepted STT bindings during dispatch holds. Capture and
  attachment still enforce source intervals, allocation, profile and settings.
  Actual binding removal remains ineligible. The design source records this narrow
  correction; dispatch behavior is unchanged.
- STT-unavailable callback regression failed because no notification reached the
  suspended room diagnostic receiver (2 tests, 1 failure). The callback now sends
  an asynchronous scoped hint while completing STT cleanup. Missing diagnostics
  does not prevent cleanup. Focused query/notification selection passes 8/8.
- Configured transfer now requires the same service, open run and current capture
  after agent transfer, then matching second-turn text/audio correlation.
- Ported old coordinator failure acceptance to room/input tests rather than keeping
  two discovery owners. Additional room tests cover stale readiness, slow provider
  discovery, page insertion, missing profile acknowledgement, collector exception,
  grant invalidation during allocation and dispatch-hold continuity.

## Verification so far

- Calls composition: 4/4 passed before the hold/notification edits.
- Configured routing: 1/1 passed after the hold correction.
- Configured diagnostic calls: 10/10 passed on the new composition, including the
  retained collection off/on crash/hang parity cases.
- Engine diagnostics, STT diagnostic boundary, input snapshot and notifications:
  251/251 passed before the additional seven room-service regression ports.
- Expanded room selection passes 27/27; the slow-discovery fixture initially raced
  initial reconciliation/pagination. Starting without a port before suspending the
  source makes the intended discovery timeout deterministic.
- Final Engine diagnostic/source-boundary selection passes 296/296. Calls
  composition rerun passes 4/4; runtime configuration passes 12/12.
- Independent Astra final review passes 53/53 with no remaining findings. Its
  completed-result expiry and actual planned-room teardown/restart-exhaustion
  probes are retained in RoomServiceTest and RoomCompositionTest; 30/30 pass.
- Root format, warnings-as-errors compile, strict Credo and unused-lock checks pass;
  Lean builds successfully and its replay test passes 1/1. Adding lifecycle hints
  crossed the RoomAuthority size limit; extracted the notification callback adapter
  and moved the unchanged ingress-binding predicate to ConnectionLifecycle.
- Full suite, broader fresh-root/unresolved-start evidence, later migration
  acceptance and milestone completion remain open. No deployment.
