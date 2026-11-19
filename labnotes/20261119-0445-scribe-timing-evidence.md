# Scribe timing evidence

- Continued after capture-admission checkpoint `f28cfd79`; clean worktree.
- Next C gap is provider timing at its owning boundary. Added an optional fenced
  capture handle to the real Scribe socket and continuous VAD adapter. The handle
  is internal, not a public provider setting, and cannot bypass durable authority.
- Socket callback samples same-VM monotonic microseconds before JSON decoding;
  permitted partial/segment messages carry that stamp plus handle token to the
  adapter. Disabled/revoked handles keep the original transport message shape.
- Nonblank committed segments produce commit landmarks but no endpoint. Only the
  existing committed-text/no-outstanding-draft silence branch supplies provider
  end evidence. Adapter emission is sampled separately at canonical turn-end
  emission. Diagnostic offers happen after successful/discarded canonical emission
  and never alter its result. Packets contain allocation/turn references, fixed
  landmark kind, timestamp and accepted-sample cursor; never text/provider JSON.
- Focused tests first failed for absent capture and absent overflow accounting.
  After implementation, affected adapter/socket/diagnostic suite passes82tests/0
  (4excluded). Test suspends the adapter to distinguish socket receipt from adapter
  processing, confirms commits alone do not settle, and checks revocation and
  saturation preserve recognition. Callback fixture forwards with allocated wire
  identity; it does not claim a real network exchange.
- Optional internal handle wiring is not automatic active-call subscription.
  Manual/historical Scribe timing, manual commit sent, source privacy association,
  room/response correlation and full report persistence remain open. Checkpoint C
  tasks remain unchecked. Astra review and static/Lean checks are running.

- Root format, warnings-as-errors compile, strict Credo, unused-lock checks and
  `bin/verify-lean` pass. The older umbrella run passed Engine2584/0 and Calls424/0
  after its MCP startup-ack failure; other apps are still running. The affected
  MCP file independently passes3/0 with seed105351. Cause of the umbrella timeout
  remains unproved; no MCP production/test behavior was changed here.

- Astra xhigh final review clean. Independently ran85tests/0 (4excluded), including
  temporary probes for multi-segment/outstanding-draft semantics, revocation after
  receipt before adapter processing, and projection loss before processing. No
  revoked landmarks leaked and ordinary recognition was preserved.
