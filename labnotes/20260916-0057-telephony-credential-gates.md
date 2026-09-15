# Telephony credential gates

## Scope and starting state

- Previous goal turn made progress: existing Zenmux migration and checkpoint acceptance were
  committed. Started this slice from clean `9dbc0c6`; progress is 3 of 7 checkpoints complete.
- Add exact private service/credential resolution and transactional active-binding guards for
  definition save, publish and web preparation, including later phone destinations. This is an
  enabling part of checkpoint 3; canonical plan references and Gateway live readers remain pending.
- Independent design review caught an incoming-admission transaction hazard: putting an outer
  guard around its current nested insert transaction would abort the transaction needed by
  concurrent-duplicate recovery. Keep its final guard with the next admission/identity change,
  preserving conflict recovery outside a failed transaction. No incoming-guard completion is claimed.
- Private snapshots stay out of definitions/plans. Exact credential ID, tenant, provider, active
  status and payload validation are required; a same-name replacement is not an equivalent binding.
- Added focused DB tests before implementation; results and review follow below.

## Verification and adjustments

- Focused red: 13 tests, 7 expected failures (missing service snapshots/guards and writes allowed
  without tenant services). Initial green attempt exposed an incorrect outage fixture using a
  nonexistent Repo module; moved outage assertions to the existing dynamic-Repo outage fixture,
  preserving the distinction between repository unavailability and a programming/configuration error.
- A focused duplicate prepared-call assertion then failed because the first error mapping hid
  `call_id_conflict` behind a credential error. Restricted translation to repository availability
  errors; write conflicts propagate unchanged. Focused group now passes 13 tests.
- Existing phone workflow fixtures now supply explicit, finite test repository bindings. They
  remain database-neutral tests of revision/route/claim behavior. The new PostgreSQL group proves
  actual encrypted service resolution and transactions; no production fallback or bypass is added.
- Focused group: 13 tests, zero failures. Calls: 81 tests, zero failures. Persistence: 106 tests,
  zero failures, 6 excluded. Root format, warnings-as-errors compile and strict Credo pass.
- Independent GPT 6 Astra xhigh review found no implementation blocker. Corrected the port docs
  to distinguish metadata fetches from private resolution and require a shared transaction context
  for guarded writes. Incoming final insertion, canonical identity and live readers remain pending.
- Rechecked the user's provider-scope clarification against the milestone and source inventory:
  only existing Google, Deepgram, Zenmux, Telnyx and Twilio integrations are included. No speculative
  provider/auth implementation was found in the current checklist or this slice.
