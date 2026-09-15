# Retain leg media auth

## Boundary and dependency order

- Start from clean `f35299b`. The previous goal turn committed durable tenant/service identity,
  corrected a missed carrier fixture constructor and recorded full verification. It made progress;
  no blocking condition prevents the remaining credential-reader work.
- Twilio WSS currently rereads the service registry. Replace that credential reader with the
  initialized configuration retained by the existing leg/admission reservation. This lifetime
  boundary must work before registry/leg construction moves to tenant database reads, so admitted
  media does not acquire a new database-availability dependency.
- Extend existing admission entries; do not add an authentication-lease subsystem, credential
  rotation workflow or provider/auth shape. The initial DB-backed service reader remains pending,
  so this slice alone cannot complete carrier checkpoint 4.
- A bounded private lookup returns the retained configuration without consuming, installing a
  waiter or extending expiry. Verify the existing exact public WSS URL/signature, then consume
  against that same immutable configuration. Pending binding must match tenant/provider/service/
  ingress/account. Token identity already owns its exact leg; revoked/replaced tokens cannot adopt
  a later leg or reservation.
- Independent design review identified two bypasses to close together: generic token consumption
  must reject protected Twilio entries, and a generic reservation must never settle a Twilio
  binding for an unsigned waiting consumer. Preserve the endpoint's enabled check separately
  from service resolution. Repeated issue/reserve inputs may reuse a token only with identical auth.
- New protected Twilio admission requires a tenant-scoped initialized service; application scope
  supplies no tenant authority and is rejected. Telnyx retains its existing token-only media path.

## Red tests

- Added focused admission/HTTP cases before implementation for retained credentials and origin,
  pending authorization, exact consumption, expiry/replacement, missing auth, disabled ingress,
  tenant mismatch and unsigned cross-provider bypass. Existing unprotected token tests remain.
- The initial run reports the expected missing private admission APIs; its old WSS reader also
  enters token consumption for an unconfigured pending reservation instead of rejecting it.
  Full red-run and implementation evidence follow below.

## Implementation and focused verification

- Initial red run: 18 tests, 9 expected failures from missing private APIs and the old registry
  fallback entering consumption. After implementation, all 36 focused admission, HTTP media,
  incoming activation and outgoing-leg tests passed.
- Added two-tenant isolation and both admission-process-loss boundaries. The latter were confirmed
  red together: 8 HTTP tests, 2 GenServer exits. Narrow catches wrap only lookup and consumption,
  discard exit details and return the existing sanitized 503. No registry fallback is introduced.
- Final focused group: 39 tests, zero failures. Logs are under ignored `tmp/`:
  `retained-media-auth-red.log`, `retained-media-auth-unavailable-red.log` and
  `retained-media-auth-focused.log`.
- Independent GPT 6 Astra xhigh review found no remaining identity, bypass, lifetime or privacy
  blocker after reviewing the catches and both loss tests. It confirmed private configuration is
  excluded from WebSocket initialization and redacted in admission-state inspection.
- Updated the service design and milestone/index evidence. Checkpoint 4 stays partial until
  initial DB-backed construction and webhook/REST credential readers are implemented.
- Existing Telnyx/Twilio carrier harnesses and voice/status/event HTTP tests pass: 41 tests,
  zero failures (`tmp/retained-media-auth-carrier-focused.log`). Format check, compilation with
  warnings as errors, strict Credo and unused-lock check pass. Full umbrella run follows this
  small reviewed checkpoint; the previous full run's native audio timeout remains recorded.

## Full umbrella verification

- At `ba83192`, the root suite completes 1,599 tests, one failure and 38 exclusions with seed
  235296, module preloading, one require and four cases. Gateway has 424 tests/one failure;
  MCP 37, Agent Runtime 95, Engine 697, Calls 84, Artifacts 20, Persistence 136 and Console 106 pass.
- The failure is `HumanTransferWebRTCTest`'s repeated-transfer listener assertion at line 355
  (test declared at 214). It expected Morse `E`; the final flush held text `E `, 25 total windows,
  23 silence windows and no pending marks. The identical state was already recorded in
  `20260916-0000-tenant-telephony-services.md`; no native test source changed in this slice.
- The unchanged isolated case passes with the same seed/preload/concurrency settings: one test,
  zero failures, 67 excluded, 112.7 seconds. This does not establish the full-suite cause.
- Logs: `tmp/retained-media-auth-root-test.log` and
  `tmp/retained-media-auth-native-isolated.log`. The new carrier-reader tests were written while
  the existing root process ran, then separately confirmed red; this root evidence is for the
  committed `ba83192` implementation. Full milestone acceptance remains open.
