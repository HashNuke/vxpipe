# Settings restart authority

- Added acceptance coverage for existing behavior, without changing runtime code: a settings loader error followed by same-revision recovery, and independent reader/projection crashes followed by a new durable read.
- Each case queues real PCM capture before failure, denies new handoffs while settings are unavailable/unknown, then consumes the old queue only after recovery. Old audio is rejected and releases its retained byte/count charge; a newly created handoff accepts fresh audio.
- Controlled loader replies and process monitors establish ordering without sleeps. The reader remains blocked until the test supplies the new durable snapshot. These are boundary fixtures, not a live database outage or configured-call provider-parity test.
- Initial focused projection/handoff/peer run: 21 tests, zero failures (`vxpipe-settings-recovery.log`). Tests start green because they validate previously implemented behavior, not a new behavior change.
- The broader settings-failure milestone task remains open pending configured-call/persistence and other listed acceptance evidence.
- Root formatting, warnings-as-errors compilation, strict Credo and unused dependency checks passed. Full suite remains deferred; no runtime source, speech state machine, provider or deployment change.
- Astra review found no issues; independent projection suite passed 13/13 (`vxpipe-settings-recovery-review.log`). Recovery happens before the old lease deadline, so rejection proves failure/restart fencing rather than incidental expiry.
