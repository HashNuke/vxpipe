# Credential cutover scope

## Decision

The 2026-09-15 user clarification limits the credential milestone to moving existing provider
credential readers into tenant database storage, removing obsolete configuration paths, and
verifying those boundaries. Existing transfer, recovery and carrier features supply the callers
of those readers. They are not new features or separate end-to-end acceptance projects here.

The earlier plan included third-party credential lifecycle work that the user had not requested.
Remove it. Vxpipe does not prescribe when tenants rotate their upstream API keys or orchestrate
that rotation with Google, Deepgram, Telnyx, Twilio or other providers.

The user explicitly retains **platform encryption-key rotation**. The platform operator owns
that key. Re-encryption replaces the protection around stored credentials while preserving their
plaintext values; it does not change a provider's API key or webhook token.

| Keep | Why |
| --- | --- |
| Encrypted tenant credential storage and trusted provisioning | Required to replace environment/global secrets. |
| Inline provider/model/options and removal of profiles | Existing approved configuration ownership. |
| Each existing AI/speech/carrier reader uses the correct tenant binding | The requested runtime change. |
| Focused missing/wrong-tenant/inactive credential and no-fallback tests | Proves the new source is authoritative and isolated. |
| Carrier command, webhook and WSS authentication checks | Credentials are also read for inbound verification, not only outbound calls. |
| Tenant service and live/persisted lookup isolation | Prevents selecting another tenant's credentials when aliases or provider IDs match. |
| Platform encryption-key replacement and re-encryption | Explicitly retained operator-owned responsibility. |
| Platform env, shared bucket, database aliases and obsolete-reader cleanup | Existing explicit user requirements. |

## Removed scope and alternatives

- Third-party API-key rotation/revocation commands, carrier verification-key overlap and provider
  credential schedules are outside this task. Existing inactive-status checks remain in readers.
- Full reception-to-billing-to-reception, private-briefing, press-1, bridging and spoken-recovery
  demonstrations repeat the owning call-flow milestones. Use focused integration checks to prove
  credential propagation and preserve the existing umbrella regression suite.
- General backup/restore drills and legacy profile-conversion frameworks are not required by this
  reader migration. Document the concrete schema cutover using existing administration; add
  migration code only when an actual persisted-data requirement demonstrates its need.
- An SDK's installed adapter list does not create new provider feature commitments. Preserve
  Vxpipe's existing supported provider/auth behavior while changing the credential source.

## Implications and verification

The milestone contains seven checkpoints. Checkpoint 6 covers only platform encryption-key rotation.
At the scope correction, one checkpoint was complete, two were partial and four were not started;
changing scope did not count as implementation. Current progress and test evidence are recorded
in the milestone ledger linked below.

The unfinished round-trip test fixture/server changes were discarded before further work.
This correction changes documentation only. Review evidence and validation are in the
[scope labnotes](../labnotes/20260915-2151-credential-milestone-scope.md); implementation status is
in the [milestone ledger](milestones/tenant-provider-credentials-and-platform-configuration.md#evidence-ledger).
