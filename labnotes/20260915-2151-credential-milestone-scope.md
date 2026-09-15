# Credential milestone scope

## User clarification and decision

The user challenged third-party credential rotation and transfer/recovery work in a credential
migration: existing paths should read credentials from the database. The earlier plan had grown
into broad call-flow acceptance and credential lifecycle features. That was an over-scoped plan.

The user then explicitly retained encryption-key rotation because the platform operator owns
that key. Keep that operation distinct: it re-encrypts stored credential values and does not
replace an upstream API key, coordinate with a provider or impose a tenant rotation schedule.

## Changes

- Narrow checkpoints 2–5 to existing credential readers and focused adapter/authentication tests.
  Preserve tenant isolation, no-fallback checks, inbound signature verification and non-consuming
  Twilio media authentication; these are required credential boundaries.
- Replace checkpoint 6 with platform encryption-key rotation, bounded resumable re-encryption,
  old-key retirement evidence and restart verification. Remove third-party rotate/revoke commands,
  token overlap, full transfer/recovery demonstrations and general backup drills.
- Keep inline selections, encryption, safe save/publish/prepare checks, supported provider behavior,
  `env.sample`, the shared bucket, approved database aliases and obsolete-reader deletion.
- Keep a concrete old-schema cutover requirement using existing administration; do not build a
  generic profile-conversion framework without a demonstrated data migration need.
- Synchronize the milestone, index and current opening migration guidance. Add the focused scope
  decision and retain completed implementation evidence separately from the scope correction.

## Worktree hygiene

At the start of this goal turn, `d70f7b1` was the clean worktree baseline and all five root gates
had passed (1,510 tests, zero failures, 30 exclusions). A new agent round-trip fixture and a
multi-request extension of the synthetic Google server had just been started. No new test or
production behavior had shipped. Discarded those exact owned, uncommitted changes and the empty
agent-transfer labnote after the user's clarification. Existing commits were not undone.

The resulting scope checkpoint changes documentation only. It does not claim any additional
credential-reader implementation. The ledger still has seven checkpoints: one complete, two
partial (AI/speech readers and platform configuration) and four not started (Telnyx, Twilio,
other supported providers and platform encryption-key rotation).

## Review and verification

Local review checked every checkpoint against the clarified ownership boundary. New reads still
require tenant/provider/service identity and safe failure before provider work. Platform key
rotation changes only encryption, with unchanged upstream plaintext values. Dependencies no
longer require all carrier flows before encryption-key rotation. The earlier independent review
applied to the prior specification; final independent review remains pending after the reviewer
usage limit. No independent approval of this correction is claimed.

Documentation validation passed: the worktree contains exactly the five intended document paths;
all 144 relative file links resolve and all three embedded JSON examples parse. The seven numbered
checkpoints match the seven ledger rows, checkpoint 6 is platform encryption-key rotation, and the
explicit storage, database, visible sample and obsolete-reader requirements are retained.
`git diff --check` passed.
The prior root suite remains the latest runtime evidence; no new runtime test pass is claimed.
