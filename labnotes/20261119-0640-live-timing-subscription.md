# Live timing subscription

A running Scribe session previously received no dynamic diagnostic subscription:
the channel forwarded only to ConversationalSTT, and the socket/continuous adapter
only accepted a handoff at startup. The retained already-running-session test
failed waiting for wire subscription before implementation.

The existing channel subscription now reaches direct Scribe and nested recognizers.
Only the current consumer of the current ready allocation may request forwarding.
Nested wrappers forward the original handoff, retaining its original owner and
lease; handoff.owner need not equal the immediate wrapper consumer. The source
capability's AudioTap still owns policy/source admission and validates its owner.
The wrapper forwards even with operational VAD disabled. Supported sockets accept
an asynchronous update only from their callback owner and only for a current grant.
Replacement revokes old capture; no recognizer/model/socket is restarted.

The fixture wire now executes the real ScribeSocket frame callback with its current
subscription state. Tests cover direct and nested already-running sessions,
prospective receipt, fixed generation/provider-turn identity, socket owner checks,
foreign consumers, revoked/replaced handles and unchanged ordinary settlement.
Nested provider landmarks intentionally retain inner allocation/turn identity;
canonical-turn correlation remains future work, not a fabricated shared ID.

Affected suite288/0 (5excluded), format, warnings-as-errors compilation, strict
Credo, unused-lock check and Lean pass. Astra xhigh review is clean: 13 independent tests/probes cover subscription,
unsupported transports, idempotence, original-owner death and channel fences.
Automatic source discovery/attachment, manual Scribe instrumentation and report
correlation remain open. The active umbrella run predates this subscription change.
