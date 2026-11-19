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

While the umbrella suite remained source-frozen, isolated temporary probes used
already-built modules in a separate Elixir VM (no Mix compilation, repository edits
or build writes). The initial API probe failed4/4 for discarded acknowledgement;
adding a socket-forwarding probe then failed1/5 for the missing profile message;
a cache probe failed before its adapter handler was added. Candidate files remain
under /tmp, not installed in the repository:
- /tmp/vxpipe_scribe_profile_candidate.ex
- /tmp/vxpipe_scribe_socket_profile_candidate.ex
- /tmp/vxpipe_scribe_continuous_profile_candidate.ex
- /tmp/vxpipe_scribe_profile_red_test.exs

Candidate probes7/0 and existing Scribe/protocol socket tests12/0 pass. The proposed
socket sends one separate bounded profile message before its unchanged ready event;
manual adapters ignore this unrelated optional message. Continuous Scribe caches
only validated canonical values before readiness, independent of capture state,
and ignores malformed/stale/repeated profile messages. These are prototype checks,
not configured runtime acceptance. Transfer the tests and repeat repository red
before installing the candidate once the frozen root run finishes. Authorization,
wrapper forwarding, coordinator pairing, Calls schema and actual session acceptance
are not yet implemented. Logs: /tmp/vxpipe-scribe-profile-cache-green.log and
/tmp/vxpipe-scribe-profile-compatibility.log; red logs use the corresponding
profile-red, profile-socket-red, profile-validation-red and profile-cache-red names.

The frozen mapping umbrella suite completed exit0 before transferring any runtime
or test changes. All applications pass, including Engine2731, Calls434, Gateway891,
Persistence579 and Console591. Repository acknowledgement/session tests are now
being added before installing the candidate implementation.

Implementation now includes the compact handshake cache, separate authorized query
through direct/wrapped sessions, source/profile join before collector admission,
and typed immutable Calls/Persistence acknowledgement fields. Source-only discovery
keeps its original API; the coordinator requests profile metadata separately while
retaining one bounded pending discovery. The query is owned by the existing
DiagnosticSubscription module; a convenience Channel delegate was removed to keep
Channel under its enforced size limit.

Repository red8/8 (missing API/message) progressed to green. Real Scribe coordinator
fixtures failed14/2 for missing context and incorrectly admitting empty echoes.
Review reproduced audio arriving between the discovery and profile requests; the
retained regression failed15/1. The matching announced-proof fallback now requires
original token/owner, current handoff/grant, source proof, policy/generation and
deadline; replacement or consumed proofs cannot recover an old query.

Manual direct/wrapped probes failed6/2 for absent unsupported replies, then passed
with explicit replies while ordinary manual inference/input continued. Existing
capture subscription preservation is retained. A new fixture's one-second real
poll boundary was replaced with the existing injected clock and explicit poll/
reader/projection barriers; no production timeout was relaxed.

Calls schema red7/1 and real storage red17/1 (decoder missing the new keys) became
green. Review then reproduced floating sample_rate acceptance; a retained red7/1
regression now passes with strict integer equality. New provider acknowledgement
fields remain optional for legacy records, closed to arbitrary metadata and
immutable across revisions.

Current evidence: Engine affected matrix752/0 (9 excluded), Calls schema/diagnostics
39/0, real persistence17/0, root static gates and Lean model/replay pass. Engine
Astra final review is clean with coordinator25/0 and session/authorization9/0.
Calls/Persistence Astra final re-review is clean with28/0 after the integer-rate fix. The full umbrella
pass recorded above predates this checkpoint and is not claimed as its acceptance.
Production composition, configured-call acceptance and remaining C tasks stay open.
