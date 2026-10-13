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

- Consolidation checkpoint: one shared directory surface for production and
  Storybook, created-age metadata, effective server Setup capability, skeletons,
  normal empty/error copy, no dashboard shortcut duplication or retry buttons.
  Retired the old setup-nudge and duplicate directory stories; sample setup's
  compatibility directory reuses the shared presentation without its nudge card.
- Red tests caught missing dates, old retry buttons, plain loaders and missing
  Setup projection. Setup test initially used a read-only membership with a write
  grant; corrected the positive case to read_write while preserving the denied
  read-only case. The full umbrella run loaded the earlier fixture, so its single
  failure is covered by the passing focused test and a final full rerun.
- Green: 719 frontend tests, TypeScript, ESLint, 14 navigation endpoint tests;
  Storybook static build succeeds. Desktop/mobile list captures, empty/loading
  states and dashboard error inspected; full umbrella gates still running.
- The shared picker now replaces the older dropdown in Directory stories; its
  chevron has the same 12px horizontal inset as its text. No extra picker-only
  padding workaround was necessary after consolidation.
