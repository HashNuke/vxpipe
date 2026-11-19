# Scribe profile acknowledgements

Research while the source-frozen umbrella run for3bb91f18 is active. No runtime or
test files have changed during that run. This is a plan, not implementation.

Evidence: STTProtocol.decode returns the session_started config; Scribe.decode
checks only present known fields, permits missing fields for speech compatibility,
and then discards the config. ScribeSocket forwards the stripped ready event.
SourceAttachment invokes its collector factory before binding capture. Calls
Collector requires a validated immutable LatencyRun.profile before its first write.
Therefore requested settings cannot serve as acknowledged diagnostic evidence.

Next bounded contract, reviewed by Astra xhigh:

- Keep a compact allowlisted acknowledgement at the Scribe handshake, even while
  capture is off. Keep requested and acknowledged values distinct; omitted values
  remain unknown. No credentials, raw config, session identifiers or transcript.
- Preserve the existing speech-ready payload and missing-field compatibility.
  Explicit mismatches retain the existing operational rejection behavior.
- Add a separate authorized diagnostic profile request through Channel and the
  conversational wrapper. Do not reuse observer replacement: it revokes handoffs
  and may alter inference taps. Retain existing owner, consumer, readiness,
  generation, allocation and current-settings checks.
- Preserve canonical discovery allocation generation through the wrapper and
  authenticate inner provider generation through its Channel. Bind the reply to
  the pending probe handoff/token/grant, rejecting stale or mismatched replies.
- Pair the source-ready and profile replies in the coordinator's existing single
  bounded pending probe before creating the immutable collector run. Timeout,
  absent support or missing profile closes only diagnostics. No synchronous
  socket query, provider RPC from audio callbacks or unbounded pending list.
- Admit the specified continuous Scribe v2 live profile only when supported;
  manual/historical profiles retain protocol coverage without spawning a second
  model stream beside existing operational inference.

Smallest red tests must cover acknowledged versus omitted echoed fields or empty
config, unchanged ready behavior, compact allowlist bounds, direct/wrapped identity binding, off-to-on
capture, stale/duplicate replies and unchanged audio while a profile is unavailable.
Extend the Calls-owned closed profile whitelist and Persistence codec to retain
bounded acknowledgement provenance and Scribe VAD parameters, distinct from
observer configuration, before the first immutable run write. Then wire validated
profile plus observer configuration into Calls-owned run construction and exercise
real configured-call persistence. A missing config object remains a protocol error;
only omitted fields within an existing config retain speech compatibility. The root suite for
source-sample mapping must finish before these runtime/test edits begin.
