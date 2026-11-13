# Incoming caller identity

- The inspection presenter used the receive connection's configured destination
  as the caller identity. Incoming admission validated the carrier `from` but
  discarded it before persisting the call, so historical calls cannot recover it
  from the original Vxpipe records.
- SIP billing CDRs showed a username, but that was incomplete evidence: the actual
  `call.initiated` webhook contained separate numeric `from`, `from_sip_uri` and
  `caller_id_name` fields for the linked call. A later Linphone attempt supplied
  the SIP address in `from` without a numeric caller ID. Do not infer an actual
  webhook identity from billing CDR summaries or display names.
- Added nullable incoming `from`/`to` address columns on the prepared call. Keep
  them separate from the existing outbound E.164-only number fields so SIP
  identities remain valid and the immutable routing plan stays unchanged.
  Hide addresses from derived Inspect output, matching outbound number handling.
- At the user's request, additionally preserve `caller_id_number`, `caller_id_name`
  and `caller_sip_uri` as separate columns. Telnyx optional metadata is bounded;
  the source's E.164 number alone determines numeric caller ID. Normalize SIP
  scheme/host while preserving user case and URI parameters. No domain is invented
  for a bare username, and display names never become numeric caller IDs.
- Presentation uses the stored inbound identity for the entry caller. Historical
  missing sources and receive-only transfer participants have no fabricated
  caller number. WebRTC and dial destinations retain their existing rendering.
- Red regression: two persistence tests and three presenter cases failed on
  missing source data and incorrect destination fallback. Green: 8 persistence
  and 13 presenter tests pass, covering E.164, SIP, missing historical identity,
  database reload and duplicate admission.
- Extended red-green coverage through the carrier decoder, persistence, JSON
  adapter and React details: 7 decoder, 8 persistence, 14 presenter, 10 Console
  adapter and 27 relevant React tests pass. Root package build/typecheck and all
  42 package tests pass.
- Browser: actual authenticated page redirected to login; no session/password
  was changed. Rendered the real CallDetailsPage components with controlled data
  in isolated headless Chromium at desktop and 390x844. Verified separate number,
  SIP and name rows plus SIP-only "Not provided" number state. Temporary preview
  files are outside the repository and load no environment files.
- Verified the SIP source number belongs to the connection. Its caller-ID
  override was blank; configured the owned number for normal outbound calls.
- Deployed additive migrations and release. The live TLS SIP/RTP test omitted
  the display name and still persisted the expected numeric caller ID plus
  normalized SIP URI; caller ID name remained null. Received greeting and model
  reply audio, stayed connected for 30 seconds, then ended on the client's BYE.
  The call row and gateway cleanup completed, with no provider warnings/errors.
- Restored only the linked historical call from its matching Telnyx initiation
  webhook. The bounded update matched tenant, public call ID, provider connection,
  leg and session IDs, and only filled previously null fields. Exactly one row
  changed. Production inspection returned distinct correct caller ID/SIP fields
  for both the restored call and the new test call.
- All 1,141 Console JavaScript tests and all 42 Core/React tests pass. Final
  required umbrella checks pass: format, warnings-as-errors compilation, strict
  Credo, unused dependencies, Lean verification and the full default test suite.
  The final run has no failures, including Engine (2,452), Gateway (887),
  Persistence (533) and Console (569); existing integration exclusions remain.
