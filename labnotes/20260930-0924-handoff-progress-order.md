# Handoff progress ordering

## Current evidence

The phone-recovery checkpoint root run (seed 149103) ends with 2,924 reported
checks, one failure, 74 exclusions. Its two new Gateway synthetic speech checks
pass. The failure is the prior `after_speech_adoption` preparation scenario,
timing out at the second destination `transfer.progress` speech blocker wait.
This is distinct from zero-PCM phone acknowledgement completion.

`HumanMediaHandoff.report_readiness/2` emits only when blocker kinds differ.
Resource reconciliation can replace a speech allocation while preserving the
same blocker kinds. A test requiring a second identical progress message treats
notification emission as a synchronization acknowledgement it does not promise.
The case already asserts the first speech blocker, then sees a fresh controlled
replacement transport before providing its Connected acknowledgement.

## Next check

- [x] Inspect the selected same-seed unmodified scenario.
- [x] Verify the existing failure against its intended admission contract.
- [x] Replace unsupported progress synchronization with evidence that native
  activation remains closed until replacement speech is acknowledged.
- [x] Run selected handoff and root gates; no timeout increase or production
  progress/reconciliation change without a demonstrated runtime violation.

At this investigation's start, no runtime fix or root acceptance was claimed.
ElevenLabs private phrase configuration and HTTP parsing progressed independently
after CallEngine root tests completed;
its ten local checks pass, registration/UI/live/gates remain pending.

## Fixture correction

The initial root failure is the red evidence for the existing unsupported
progress synchronization. Selected same-seed unmodified and corrected cases
were run separately; their terminal results are recorded below.
Replaced only the second duplicate progress wait with the existing bounded
native-activation exclusion check while the replacement lacks its Connected
acknowledgement. The case still requires initial speech blocker notification,
a distinct replacement transport, subsequent activation, unchanged media
instances and final room readiness. Removed the now-unused wait helper.
No production progress publication, reconciliation or timeout was modified.

## Selected results

Both selected same-seed processes are terminal, exit zero. The unmodified case
passes (153.9 seconds total, 5.49 seconds case execution); this reproduces the
previous intermittent pattern but does not show a repair. The corrected case
also passes (164.2 seconds total, 6.62 seconds execution; 1/0, 67 excluded),
retaining blocked-before-acknowledgement and ready-afterwards evidence.
The following root verification covered only the two Gateway fixture corrections.
The new unregistered ElevenLabs files were preserved outside the worktree while
this checkpoint ran, keeping its gates scoped to the fixture corrections.
Format, warnings-as-errors compilation, strict Credo and unused dependency
checks all pass. That root run terminates with 2,924 tests, one failure,
74 exclusions: the RTVI departure case lacks a server readiness acknowledgement
before room shutdown. No handoff preparation failure recurs in this run.
The subsequent root run includes all three fixture corrections and is terminal,
exit zero: 2,924 reported tests, zero failures, 74 excluded, seed 149103.
All 522 Gateway tests pass, including the preparation scenario. All five root
completion gates pass. This accepts the test fixture checkpoint; pending
ElevenLabs implementation and shared provider milestone gates remain unchecked.
