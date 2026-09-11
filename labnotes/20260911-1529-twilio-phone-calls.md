# Twilio phone calls

## Scope and current-provider research

Milestone 18 must run the existing provider-neutral incoming-call and private human-transfer path
through Twilio without changing participant definitions or room orchestration. Docker packaging and
whole-call retention remain outside this work and behind the user-requested post-milestone-22 review
hold.

Current Twilio documentation was checked on 2026-09-11. Incoming Voice webhooks are form-encoded
requests which must receive TwiML. Bidirectional media uses `<Connect><Stream>` over WSS. Its wire
format is fixed mono `audio/x-mulaw` at 8 kHz; inbound messages include connected, start, media,
DTMF, mark, and stop, while outbound control supports media, mark, and clear. A returned mark is the
playback acknowledgement for a previously queued media/mark pair. Request authentication uses
`X-Twilio-Signature`, HMAC-SHA1 over the exact public URL plus sorted form parameters. The initial
WebSocket upgrade must be signature-checked too.

Outbound calls use the form-encoded Calls REST resource with HTTP Basic authentication. The call's
`Url` supplies TwiML for its bidirectional stream; `StatusCallback` supplies initiated, ringing,
answered, and completed progress with a `SequenceNumber`, and async AMD supplies `AnsweredBy`.
Unknown command outcomes remain no-retry. We will select async `MachineDetection=Enable` only when
the configured service enables detection, then wait for the existing explicit press-1 acceptance
after a human/unknown result. Media/AMD stream-count interaction must be verified in the live lane.

The first genuine common-contract gap is provider identity. Twilio supplies Account SID and Call
SID but no distinct equivalent of Telnyx's call-session ID. Account SID is the configured provider
connection identity; Call SID is both the addressable call-control resource and exact provider leg.
The optional session field must therefore remain `nil` for Twilio instead of copying the Call SID
and falsely claiming three independent identifiers. Exact comparison still includes the optional
field, so a carrier that supplies one cannot lose it.

Implementation checkpoints planned from this evidence:

1. Make provider session identity optional across common admission/persistence/media contracts.
2. Add provider-specific configured-service validation and Twilio form-signature/webhook/TwiML
   ingress without adding Twilio data to participant definitions.
3. Add no-retry REST dial/end operations and exact status/AMD correlation.
4. Add an authenticated media socket and Membrane G.711 pipelines. Use the pure
   `membrane_g711_plugin`; do not introduce FFmpeg. If 8/48 kHz conversion has no suitable
   non-FFmpeg Membrane element, implement a narrow tested Membrane resampling element rather than an
   external process.
5. Reuse the full provider-neutral private-transfer harness for parity, then add a guarded tagged
   live-provider lane with no unapproved destination.

Official references are recorded in the milestone/architecture documentation as implementation
decisions become durable.

## Checkpoint 1 red: honest optional provider session identity

Added Calls and PostgreSQL boundary tests for an authenticated Twilio-shaped incoming event whose
Account SID identifies the configured connection, whose Call SID identifies control and leg, and
whose provider session ID is absent. The expected claim and stored telephony leg preserve `nil`.
This is project-owned normalization behavior; it does not test Twilio itself.

The Calls test failed first with `invalid_incoming_telephony_event`, as expected, because admission
required a non-empty session ID. Normalization now requires connection/control/leg and accepts only
`nil` or a non-empty session value. Its focused six tests pass.

The first persistence run then failed all five inserts. The schema patch had removed the session
field from `cast/3` instead of only removing it from `validate_required/2`, so even Telnyx values
were discarded and rejected. Restoring the cast and making only the requirement optional fixed the
regression. A forward migration changes the existing column from non-null to nullable. The focused
PostgreSQL suite now passes all five tests, including both Telnyx and Twilio shapes.

Root formatting, warnings-as-errors compilation, strict Credo, and the unused-dependency check pass.
The complete umbrella run passed all seven application lanes: MCP 37, Agent Runtime 58, Call Engine
351, Calls 45, Persistence 31, Gateway 176, and Console 59—757 tests with zero failures.
