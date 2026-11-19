# Startup gate ordering

- Investigating the failed full timeline gate (seed664729). Cartesia's startup
  timeout test observed initialization_failed instead of session_failed; the
  same-seed isolated file passed12/0. The captured root failure is the red proof.
- Session.start explicitly returns :starting. The provider opens its wire in
  handle_continue(:connect), after its init acknowledgement. Transport startup
  notification can still precede the initializer processing its start_child
  reply and issuing SessionTree's Channel.started acknowledgement. Injecting setup_timeout at that notification
  legitimately races initialization completion. ScopeControl already classifies
  failure from the initializer separately from failure of an admitted tree.
- Corrected only this pre-readiness test to accept those two fixed lifecycle
  failure reasons while retaining the exact allocation and owned-transport DOWN
  assertions. Tests after provider-ready acknowledgement still require
  session_failed. No production failure behavior or timeout was changed.
- Astra is independently reviewing the Twilio harness failures with /tmp-only
  probes. Their cause and relation to prior silent-transfer issues are not yet
  established; no speculative production fix has been applied.

- Independent Astra Cartesia probes established both valid pre-ready interleavings
  (two probes pass). The focused Cartesia file passes 12/0; review is clean.
- Twilio review reproduced two distinct fixture races with /tmp probes: delayed
  prior media teardown causes media_binding_mismatch on the next reused connection;
  synthetic private-briefing output before provider Speak causes unavailable TTS.
  Both probes fail before synchronization and pass after it. This establishes
  fixture defects, not a production-media bug or the exact historical log cause.
- The harness now monitors incoming/outgoing media roots before cleanup and awaits
  their termination, and waits for the actual Speak control before emitting a
  briefing response. Focused seed664729 file passes 15/0. Astra xhigh re-review is clean.
