# Migrate carrier readers

## Reviewed boundary and implementation order

- The preceding checkpoint `ba83192` removes the WSS registry credential reader and retains
  Twilio authentication in existing admissions. Its 39 focused and 41 carrier-flow checks pass;
  the full root suite is still running while the new reader tests are written (no second Mix).
- Replace static ServiceRegistry credential lists with Calls.TelephonyServices resolution. Keep
  Gateway free of Repo/crypto and translate only existing Telnyx/Twilio auth through their current
  internal profiles. Platform public origin and transport adapter injection are separate inputs.
- Resolve ingress metadata, then its exact tenant/alias credentials; compare canonical reference
  and ingress so an intervening rebind cannot change ownership. Outbound requests carry the
  participant's full non-secret ServiceReference and the Gateway connector rejects missing or
  changed pins. Raw Engine connectors may remain unbound.
- Independent GPT 6 Astra xhigh design review requires keeping incoming verification/activation
  together: pass the verified private ConfiguredService into Leg and backend activation, removing
  CallAdmission's second registry read. Compare the claim's prepared entry before room startup
  and answer. Hosted web startup must also reject unbound/stale phone plans before activation.
- Publish the same private snapshot in owner-bound existing LegRegistry entries before admission
  or synchronous dial work. A GenServer lookup would queue behind that work and block early
  callbacks. Registry ownership supplies automatic cleanup; no new cache/lease process is needed.
- HTTP may extract bounded untrusted identifiers solely to locate an existing owner. Signature
  verification still covers the original body/exact URL before event dispatch. Verify and dispatch
  to that same PID; never relookup/create a replacement owner after verification, and never retry
  a failed existing-owner verification using fresh DB credentials.
- Live primary identity includes tenant and canonical service UUID. Outgoing local-leg-ID dispatch
  must also compare the supplied authenticated identity. New incoming legs without an owner use
  DB resolution; existing callbacks and cleanup keep their initialized configuration during outages.
- DB lookup consumes the existing outbound timeout: establish a deadline before resolving,
  reject expiry before starting/dialing, and await only the remainder. No new worker subsystem.
- Started the smallest reader tests and a typed Calls-port fixture before production changes.
  They cover the two supported carriers/two tenants, missing/changed pins, ingress rebinding,
  inactive credentials and sanitized repository failures. Expected red run is pending the prior
  umbrella process finishing. No production code for this slice has been written yet.

## Implementation and focused verification

- Replaced production static service lists with the typed Calls repository. Both existing carrier
  profiles consume current tenant auth. Removed the application fallback and reject old options
  without echoing private values. Added optional `VXPIPE_TELEPHONY_PUBLIC_BASE_URL` and its sample.
- Implemented the reviewed canonical outbound pin, incoming private snapshot handoff,
  owner-bound registry selection, exact-owner dispatch, hosted phone-plan check and deadline rules.
- Initial reader tests failed on the old static options/arity; the new reader group passes 5 tests,
  including actual encoded REST authentication for two tenants and both existing carriers.
- The Engine pin propagation test failed on the absent request field, then its 4-test group passed.
  The incoming unbound-plan test first accidentally selected the preceding test by line; the
  corrected selection failed for the missing new backend arity, then passed after implementation.
- Independent review found three production issues: altered incoming retry control/session IDs
  were accepted, valid generated tenant keys beginning with `-`/`_` were rejected, and ownerless
  lifecycle dispatch could relookup after verification. Focused red tests and guards corrected them.
  Credential lookup expiry initially still dialed; the deadline test now rejects before startup.
- A fixture edit mistakenly expanded an already 16-character tenant key to 17 characters, causing
  validation failures. Reverted it and corrected the two genuinely short scenario keys. Also fixed
  old lookup arities and one Twilio scenario whose default plan pin selected Telnyx.
- The carrier/activation/registry group passes 46 tests. The existing two signed carrier harnesses
  now make their credential repository unavailable with their storage-outage switch: 26 tests pass.
  Cleanup switches its own source unavailable and still ends the initialized exact leg.
- Public missing/revoked/unavailable credentials create no leg identity, reservation or dial.
  A selected real owner retired before dispatch cannot deliver to its replacement. Web-entry
  startup rejects unbound/stale later phone destinations before room creation. The combined group
  passes 62 tests; the final corrected outgoing-only group passes 16 tests.
- A tagged Console composition test provisions two tenants × Telnyx/Twilio in real encrypted
  PostgreSQL storage, resolves through Gateway and verifies actual HTTP signatures. All four
  correct signatures pass; each other-tenant signing key rejects. One integration test passes.
  No external carrier requests or new audio scenarios were introduced.
- The platform-origin tests first failed because runtime ignored the setting and accepted invalid
  origins; the Console configuration group now passes 5 tests.

## Independent implementation review

GPT 6 Astra xhigh independently reviewed the design and integrated reader/owner/deadline paths.
After the production fixes above, it found no remaining blocker. The final evidence review accepted
CP3/4's bounded exits subject to two test corrections: use a marker instead of a `flunk` swallowed
by the production callback guard, and exclude Console's first integration lane by default. Both are
corrected. No new provider/authentication method, upstream-key rotation or call-flow feature is added.

## Common gates

The preceding full run at `ba83192` completed 1,599 tests with one previously recorded native
Morse assertion failure and 38 exclusions; its unchanged isolated case passed. That does not prove
its cause. The current reader slice's final static checks and full root run are recorded below.

Final format, warnings-as-errors compile, strict Credo and unused-lock checks all pass.
The reviewed reader checkpoint is committed before the slower full umbrella run; its result will
be recorded separately. Checkpoints 3/4 close on their focused exits; common acceptance stays open.
