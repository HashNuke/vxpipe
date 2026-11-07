# Await queued STT onset

The integrations checkpoint's full umbrella run (seed 397067) reproduced an
existing synchronization gap in the hybrid queued-onset test. The test suspended
the room, pushed PCM and queried ingress, capability and provider state once,
then inspected the room mailbox before the asynchronous speech-session/channel
had delivered the onset. Only a usage observation was queued; the expected STT
turn_started signal was not yet present.

Use the existing bounded await_stt_turn_ref helper before inspecting that mailbox.
STT installs that reference while handling semantic speech_started and sends the
room signal in the same callback, so the later state acknowledgement proves the
forwarding callback completed. The assertion that the onset is actually queued
remains, followed by the existing activity-demand removal and stale-onset checks.
No production state-machine behavior changes, sleeps or timing allowances are added.
The full focused file passes all 37 tests with the failing seed 397067. Independent
adversarial source review is clean: the actual queued-message assertion and
subsequent demand-removal/stale-onset rejection contract remain unchanged.
The final umbrella rerun with seed 397067 passes 4,987 tests with zero failures
(218 excluded). Format, warnings-as-errors compile, strict Credo and unused-
dependency checks also pass. The separate saved-MCP acceptance lane passes 20 tests.
Exact staged adversarial re-review is clean. This is unrelated test maintenance,
not an MCP implementation requirement; it is committed separately from phone acceptance.
