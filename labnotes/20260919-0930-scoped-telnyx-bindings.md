# Scoped Telnyx bindings

- Start C1 after reviewed onboarding checkpoint `a7585f2`. B2/B3 root acceptance
  remains open for native WebRTC failures; the latest isolated speech-adoption case
  passed unchanged. See the separate native verification labnote.
- Read the parent scoped-services plan, tenant credential/authoring and Telnyx
  milestones, and current Calls/Persistence/Gateway ownership boundaries. Checked
  Telnyx's current primary documentation for account-level signature verification
  and application-owned webhook configuration.
- Design review is separate from progress: add an explicit effective credential-name
  binding, preserve exact legacy tenant links, keep one primary Telnyx verifier per
  scope, and pin selected owner/ID in prepared references. No implementation yet.
- C1 implementation deferred for the user's presence-only credential clarification;
  the design now uses the shared presence resolver and removal rather than disabling.
- Read-only C1 boundary review while presence-checkpoint umbrella verification runs:
  TelephonyService currently requires an exact tenant UUID/public key; Store locks it,
  and Gateway compares prepared ServiceReference values. Named scoped records need an
  explicit unresolved-versus-resolved contract, and the binary plan decoder must fill
  legacy defaults for newly added reference fields. Existing principal-aware telephony
  guards already compare the resolved credential owner and can be reused.
- Presence correction is reviewed/committed as `2cfebbc`. Final serial umbrella passes
  1,763 tests with 40 exclusions, including all prior native failures. C1 can resume.
- Design reviewed locally for prerequisites, no unsigned key-scope selection, legacy
  compatibility, prepared-plan defaults and public-key ownership. C1/C2/C3 remain
  unchecked until their runnable acceptance gates pass; this is a research checkpoint.
- C1 red-green: optional Telnyx public-key payload initially failed local auth validation;
  new scoped application tests then failed registration. Payload validation is green;
  scoped storage/resolution and legacy carrier tests pass (23 focused persistence tests).
  Tenant entries lacking a verifier fail without borrowing the platform key. Operator
  caller authoring succeeds; tenant update/publish fails until tenant credentials exist.
- Compatibility red-green: old binary service references initially lacked new fields;
  the decoder now supplies nil legacy defaults. Gateway ingress initially compared an
  unresolved named record's nil ID with the resolved ID; comparison now preserves the
  application identity while fresh/prepared readers pin selected owner, name and ID.
  Six Gateway reader tests pass. No UI or scoped URL exposure yet; C2/C3 own those.
- C1 migration adds nullable credential_name/ID with mutually exclusive binding checks,
  retains the legacy composite FK, makes scoped application IDs unique, and refuses
  rollback while new bindings exist. Review explicitly guarded SQL NULL semantics.
  A fifth persistence regression proves the database rejects a binding with neither
  an exact ID nor an effective name; all 24 focused persistence tests pass.
- Disposable PostgreSQL upgrade/down/re-upgrade preserves legacy service/credential
  IDs and ciphertext. Scoped configuration resolves in a fresh VM; rollback rejects
  live scoped rows atomically, and another VM still resolves them afterward. The owned
  verification database was removed. All four root static gates pass; the final serial
  umbrella run is in progress.
- Local review covered raw metadata versus resolved snapshots, fail-closed selected
  public keys, complete prepared references, legacy decoder defaults, SQL NULL checks,
  retained foreign keys and credential-owner authorization. The trusted registration
  command accepts the new binding shape; its help now describes both supported shapes.
  No UI changed in C1, and no live-provider or scoped-URL acceptance is claimed yet.
- Full serial umbrella: 1,770 tests, 40 excluded. The sole failure was an older Calls
  assertion enumerating the exact fields of a legacy reference; it omitted the two new
  nil defaults. Corrected that expectation and reran all 116 Calls tests successfully.
  The unchanged engine (700), Gateway (446), Persistence (176) and Console (180) suites
  all pass in the umbrella run. A second full media run is unnecessary for this
  assertion-only correction. Final explicit changed-file/root formatting, compilation,
  strict Credo and unused-dependency checks pass. Reviewed code, tests, migration and
  documentation together before staging the C1 checkpoint.
