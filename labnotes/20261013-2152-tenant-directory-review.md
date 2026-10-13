# Tenant directory review

- Read the supplied goal objective file and copied its requests verbatim into the
  recent sidebar/dashboard milestone. Added dependency/design review and ordered
  implementation checkpoints; reopened its index entry for the continuation.
- Initial inventory found production backend search already used by the directory
  and sidebar picker. Legacy table stories and onboarding overview coexist with
  the newer workspace list, explaining the inconsistent states and links.
- Follow explicit dashboard redirect after creation; Setup remains a permitted
  Services link. Do not invent stats from the five-row recent-call sample.

- Creation checkpoint: added standalone authorized tenant persistence and POST
  endpoint, guarded page, CSRF-bearing form and dashboard redirect. No bootstrap
  credentials or resource permissions are generated. Approved creation-only
  roles get metadata visibility while each resource capability stays denied.
- Red evidence: domain/store undefined callbacks, missing route, metadata dashboard
  404, and absent frontend creation route. Green: 2 domain, 4 persistence,
  13 endpoint tests; 28 frontend navigation tests; TypeScript check.
- Persistence test initially counted all seeded keys; corrected to compare the
  before/after count so it tests creation side effects independently of seeds.
- Browser: inspected creation at desktop and mobile; submitting the Storybook
  form navigates to its tenant dashboard. Full umbrella gates running; remaining
  directory/state consolidation is tracked in the milestone.
