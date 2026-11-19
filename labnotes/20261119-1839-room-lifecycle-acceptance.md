# Room lifecycle acceptance

## Evidence audit

The remaining reuse/fallback checklist combines contracts already exercised by the
new room-service path. This checkpoint audits them and adds the uncovered late
collector/source-removal race rather than repeating completed implementation.

| Contract | Retained evidence |
| --- | --- |
| All local Silero/collection combinations, no duplicate inference | RoomServiceTest four-mode matrix and configured four-mode matrix with exact provider PCM, inference provenance and commit checks. |
| Mid-call mode replacement and reconnect | RoomServiceTest reconnect cases switch both directions, retire old worker, change run/allocation/epoch and retain one slot. Configured routing tests separately replace actual Scribe allocation with explicit durable boundary. |
| Source appearance/removal | Accepted source snapshot reconciliation, removed-input retirement and two-human configured isolation. New pending_departure cases remove/re-admit an accepted source while collector work is blocked. This is an authoritative snapshot fixture, not a live transport join test. |
| Disable/re-enable | RoomService and configured matrices revoke capture, preserve operational cursor, forbid fallback while off and create fresh runs after enable. |
| Stale/late work | Completed attachment past deadline, late source readiness, suspended-service port loss, grant invalidation during collection, cancelled startup and new removed-source late collector completion. Worker reset/retired-epoch tests retain acoustic-result fencing. |
| Service restart, exhaustion and teardown | RoomService restart/reconciliation/exhaustion cases, actual RoomComposition acceptance and real Engine-root unresolved-start teardown. |

## Added race cases

Both local VAD modes create a collector output and hold the callback. The accepted
connection is removed while its reservation is still charged. Once released, the
late output is closed, cannot accept packets, leaves no bound tap or worker, and
releases its slot. Re-admitting the same accepted input creates fresh run/clock IDs.
Exact initial PCM and marker bytes reach synthetic Scribe; only the selected VAD
path processes the marker. Room-subtree termination and worker DOWN precede
checks for duplicate bytes/inference or extra commits. Both cases pass initially
(2/2), without runtime changes. Independent review and broader checks are pending.

## Review extensions and results

Review confirmed the existing matrix/reconnect/settings/late-acoustic tests cover
the neighboring contracts. The new cases now assert the pending attachment lease
is still current just before callback release, preventing deadline expiry from
masking the source-withdrawal fence. After fresh admission they remove the accepted
input again while RoomService remains running, then require worker DOWN, closed
capture, zero active sources and zero occupied slots.

An initial assertion expected scan to remove the active entry synchronously and
failed both cases. Retirement intentionally retains its entry/slot through worker
DOWN; the corrected assertion follows DOWN. Both strengthened cases pass 2/2.
The broader focused Engine diagnostics selection passes 234/234 before these final
assertion additions. Root static checks passed and are being repeated on the final
fixture. No production behavior changed. Independent final review is pending.

## Final acceptance

Independent scoped Astra review is clean, with the latest cases passing 2/2. Its
positive control restores the accepted connections before callback return; both
cases then fail the rejection assertion with active_sources1/attached. This proves
withdrawal, rather than expiry, is the cause of rejection. Final root static gates
pass. The lifecycle migration checkbox is now checked at the documented accepted
source snapshot scope; settings/failure parity, UI and E/F remain open. No live
provider test, Telnyx change, full umbrella suite or deployment occurred.
