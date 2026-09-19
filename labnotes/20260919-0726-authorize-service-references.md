# Authorize service references

- User clarified that operator API keys may author tenant specs using platform
  services, but tenant keys must have access to every referenced tenant-configured
  service. Updating an operator-authored spec must fail while any platform-only
  reference remains, even if that reference is unchanged.
- Inspection found only trusted host call-spec save/publish entry points; existing
  HTTP APIs admit calls but do not expose call-spec writes. Operator browser authority
  exists; installation API-key authentication does not. Added A2/A3 to the plan and
  made the user-requested operator API-key flow an explicit dependency.
- Preserve trusted host APIs, introduce a principal-aware authoring boundary, and
  enforce ownership again while holding final credential/service transaction locks.
  Running previously authorized published routes remains separate from editing.
- Red: the persisted authoring scenario lacked the principal-aware API; a direct
  final-guard regression demonstrated that an active platform credential reached
  an unauthorized write. Both failures occurred before implementation.
- Added principal-aware save/publish workflows. Tenant `admin` authority forces a
  tenant-owner restriction; installation operators use ordinary effective resolution.
  Source input cannot grant itself access. Model/STT/TTS preflight and final protected
  writes enforce the restriction; telephony guards carry the same requirement for
  the scoped carrier checkpoint. Trusted host entry points remain explicitly trusted.
- Green: 26 persistence tests, zero failures, two integration exclusions (seed
  700134). The scenario covers operator save/publish, tenant create/update/publish
  rejection, subsequent tenant provisioning and successful edit, and runtime tenant
  preference on a new call from the original operator-authored revision. Moved the
  final-guard regression into the same integration fixture after it passed.
- Calls owning suite passes 113 tests (seed 283209), including missing authority,
  calls-only keys and cross-tenant substitution. Final review checked that principal
  authorization replaces caller-supplied owner options and that protected repository
  writes repeat the ownership check before mutations.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks pass. A new complete umbrella run is in progress; the previous Twilio
  recovery gate remains explicitly open until completion. API-key issuance and HTTP
  writes follow in A3; no external operator-key flow is claimed by this checkpoint.
