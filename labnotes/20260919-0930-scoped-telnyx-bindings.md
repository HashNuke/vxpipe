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
