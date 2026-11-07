# Wire retained MCP identity recovery

## Plan and current contracts

- Static create already returns a bounded 409 reconnect proposal with retained ID
  and generation, or a connected duplicate ID. The production modal currently
  replaces both with generic close/retry text. OAuth start discovers duplicates
  only during callback persistence, after an otherwise successful consent flow.
- Reuse existing static `/reconnect` and browser OAuth `/:id/oauth` operations;
  never create another connection/grant store or resurrect a revoked record from
  an ordinary Connect. Preserve the backend's deterministic endpoint/directory
  conflict ordering and atomic persistence checks.
- A proposal is not accepted saved configuration. Before rendering retained setup,
  read tenant-authorized metadata at the existing GET route using an explicit
  retained-generation query. Require current write authority and exact revoked
  generation, with no credential decryption. Render accepted saved directory
  configuration and require fresh credential entry. Do not reuse current remote
  listing fields when an older retained snapshot owns the identity.
- Keep conflict state tied to the active endpoint/authentication/issuer draft;
  clear it on changes and cancellation. Offer review/reconnect explicitly. A
  connected duplicate opens fresh authorized management. Never trust response
  diagnostic text or identifiers without bounded parsing and tenant-scoped reads.
- Parent directory state should own transitions between new, retained and managed
  dialogs, remounting the form to discard old credentials. Retained forms use the
  accepted endpoint and generation, hide Disconnect/Refresh until connected, and
  use the existing operation appropriate to static, browser OAuth or machine auth.
- Consent retry for a retained record cannot rely on Connected inventory, which
  intentionally excludes revoked records. Recover with the same generation-bound
  metadata read, fenced by current actor/tenant/attempt and current authority.
- For browser start, add a bounded repository identity lookup reusing its indexed
  deterministic duplicate query after trusted protocol preparation and before
  attempt creation/consent. Explicit Connect may already have performed registration;
  final create remains authoritative against races. Independent design review is
  pending before implementing this ordering.

## Design review and revised ordering

Independent adversarial review accepted the retained metadata/read/intent model,
with explicit Calls write checks despite the route's ordinary read permission,
strict generation-query parsing and callback recovery bound to the saved attempt.
It identified an important limitation in post-preparation duplicate lookup:
changed listed configuration may fail preparation before revealing the reusable
retained identity, and DCR may create an unused registration. Covering those cases
requires resolving a trusted target before authentication/protocol side effects.

Use a small shared Console target resolver behind the existing connection/OAuth
ports: normalize the custom endpoint or resolve the bounded directory reference,
then return only trusted canonical endpoint and accepted snapshot. Calls checks
tenant/write authority and duplicate identity before preparation. Preparation
consumes that accepted target rather than repeating directory discovery. The
existing protocol implementation still owns all live capability/authentication
checks; there is no second discovery algorithm or public API. Reuse the exact
tenant-scoped endpoint-or-directory duplicate query with its deterministic order,
and retain atomic create as the race authority. Static and OAuth starts should
share this ordering, including changed listed recipes that cannot authenticate.

Nine initial frontend conflict regressions fail because the production modal has
no Review reconnect/Manage existing connection action. They cover explicit intent,
draft invalidation and stale/foreign/mismatched metadata. The modal now parses
bounded conflict results, loads fresh tenant/generation-bound public metadata only
after explicit review, clears credentials and asks its parent to remount accepted
management/reconnect. All nine conflict tests pass. Three retained-form regressions
then failed before adding fresh-credential setup and the existing static/machine/
browser reconnect routes. A fourth red regression protects read-only retained
inspection from a Reconnect mutation control. All 26 focused form/management/listed
tests and TypeScript pass; callback recovery and actual backend proposal/read
support were still pending at that point. The preceding listed OAuth forms and
saved-discovery checkpoint was committed separately as `ff586468` after all root
gates and independent exact-index review passed.


## Recovery implementation and review

- Four Calls retained-read regressions failed because the operation was absent;
  three endpoint assertions failed because retained queries fell through ordinary
  details and edit capability was missing. Calls now checks current write authority
  before and after the exact metadata read, rejects foreign/stale/nonrevoked records
  and returns only public configuration. The route parses bounded canonical decimal
  generations and rejects unknown retained query fields. Calls 24 / Console 11 pass.
- Real-store session/CSRF lifecycle coverage reads accepted retained configuration
  with no encryption key while the directory is offline; ordinary and cross-tenant
  reads remain 404, and no probe or directory request occurs. The existing identity
  and namespace survive explicit fresh-credential reconnection.
- Eight callback regressions initially failed. Matching denied/failed retained
  attempts now load fresh metadata; transient failures retain only the consumed
  public draft in memory for retry, under its original five-minute age limit.
  Actor changes abort late results. Read-only connected duplicate management also
  has a red/green regression; retained records still require write authority.
- Independent UI review found a dead Retry recovery button after leaving the
  callback through category navigation. The red test reproduced it; unfinished
  recovery now clears its notice as it discards pending context. All 20 return
  tests pass. Backend and UI source re-reviews report no remaining issue.
- One bounded Chrome batch at 1280x900 and 390x844 covers static conflict review,
  empty fresh credentials, explicit reconnect, accepted listing/recipe, connected
  management and cancelled OAuth setup/handoff. Screenshots show contained usable
  forms. The owned session is closed. A single confirmation batch covers the retry
  cleanup correction using the actual production callback hook.
- The first full frontend run passed 1,055 tests. TypeScript caught an unsupported
  Button variant, corrected to the incumbent default; ESLint caught two unused test
  callback parameters, corrected with the typed mock signature. Final frontend verification passes all 1,056 tests across 138 files, TypeScript
  and ESLint (only the existing SetupDialog hook warning).

## Checkpoint boundary and next work

This checkpoint completes usable recovery from existing static conflict proposals
and cancelled retained OAuth attempts. Early duplicate detection is a separate
next checkpoint: resolve a trusted target before static/OAuth authentication,
refresh authority around lookup, and bind later protocol output to that target.
Independent review recommends required new port callbacks; a legacy adapter may
return bounded unavailable before side effects, never bypass identity checking.
The public API and stores remain unchanged. Full authenticated workflow acceptance
is still open; prototype renders do not close that gate.

- The retry confirmation uses the actual OAuth return hook: temporary outage,
  category navigation removes recovery on desktop/mobile, and explicit retry
  restores the generation-bound form with empty credentials. The second owned
  browser session is closed; no additional cosmetic inspection was needed.


The first full root run (seed 362537) had one preexisting native WebRTC transfer
failure; all other applications passed, including Calls 339 and Console 533. The
wire reported policy_changed because an interrupted output frame terminated its
policy authority. A separate [output investigation](20261107-0720-inspect-transfer-policy.md)
reproduces the reply-order defect deterministically and records its isolated fix.
No MCP assertion or production behavior was changed in response to the audio failure.
After the separately reviewed output correction, all five root gates pass. The full
umbrella rerun passes 4,955 tests with zero failures (201 excluded, seed 362537).
Lean build/oracle/replay also passes for that output correction. The next
duplicate-lookup checkpoint's red tests are separate from this verification run.
