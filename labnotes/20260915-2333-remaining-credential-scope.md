# Remaining credential scope

## Audit and decisions

- User questioned whether remaining milestone work was necessary, then explicitly reiterated
  that authentication for unsupported providers is outside this milestone. No Telnyx implementation
  had begun; the worktree was clean after checkpoint 2 acceptance.
- Independent GPT 6 Astra xhigh review found remaining scope risks: unconditional non-API-key/
  Bedrock examples, prescribed carrier policy/authentication-lease machinery, duplicate keyring
  implementation and repeated broad acceptance checks.
- Limit checkpoint 5 to existing supported provider/auth paths, using pre-cutover Vxpipe source
  and project tests as the baseline. SDK adapter catalogs and website logos alone cannot create
  commitments; the interim Google-first cutover catalog cannot erase existing supported paths.
  Remove the Bedrock task entirely instead of leaving a conditional future implementation task.
- Reuse carrier options and initialized leg/reservation configuration. Keep correct tenant/service
  selection, no global fallback and authentication before token consumption. These are required
  changes to existing readers, not a new carrier feature project.
- Reuse the existing active/decrypt-key keyring. Checkpoint 6 still owns resumable re-encryption,
  concurrent-write safety, restart and old-key retirement evidence. The platform operator owns
  encryption-key replacement; third-party credentials remain unchanged.
- Final acceptance reuses valid earlier evidence and fills only changed/uncovered boundaries.
  Limit launcher/Console/Astro verification to changed wiring. Require configuration loading and
  provider construction after restart, not another full voice/transfer/recovery demonstration.
- Keep all seven checkpoint identities and dependency order. Implementation remains 2 complete,
  1 partial and 4 not started. This documentation-only correction completes no checkpoint.

## Source evidence

- `ServiceRegistry.fetch_for_tenant/3` still has application-service fallback.
  `OutgoingLegConnector.connect/3` uses it before constructing an outgoing leg.
- `TelnyxEvents.handle/3` and `TwilioMedia.upgrade/4` resolve configured services before signature
  verification. Twilio consumes a media token only after authentication; that ordering must survive
  the credential-source change.
- `MediaAdmission` already owns token entries containing ingress, leg, expiry, waiter and optional
  binding. These existing records can locate private initialized configuration without a new lease
  subsystem. `ConfiguredService` already owns carrier options and private adapter/verifier inputs.
- `TelephonyCallStore.fetch_claim/5` currently matches provider/service alias/event or leg IDs without
  tenant in the query; tenant service isolation remains required for the new DB-backed bindings.
- `CredentialKeyring` supplies current/fetch key operations and `CredentialCipher` uses stored key
  IDs. Existing keyring tests cover configuration validation and safe inspection. Full re-encryption
  transition evidence remains required; it has not been claimed complete.
- ReqLLM config currently accepts explicit API-key authentication. Project native-routing tests
  exercise `zenmux:openai/gpt-5`; this is concrete existing integration evidence. No unsupported
  provider implementation is justified by an SDK entry or marketing logo.

## Verification

- No runtime/configuration/test files changed and no Mix command was needed for this document edit.
- Documentation checks pass: all 149 local links resolve, the JSON example parses, seven ordered
  checkpoints remain, and completion status stays unchanged. `git diff --check` passes.
- Bounded independent GPT 6 Astra xhigh re-review found no blocking issue, remaining mandatory
  unsupported-provider work or broad call-flow project. It confirmed that tenant isolation,
  authentication-before-consumption, existing initialized-leg lifetime and encryption-key
  re-encryption contracts remain intact, with unchanged dependency order.
