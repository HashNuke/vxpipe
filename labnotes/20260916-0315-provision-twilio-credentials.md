# Provision Twilio credentials

- The incoming identity tests exposed an ordering prerequisite: existing Calls/Persistence
  Twilio admission fixtures currently resolve a Telnyx credential. Complete the already planned
  Twilio Account SID/Auth Token storage boundary before correcting those fixtures and enforcing
  provider/account identity. No new carrier or authentication mode is introduced.
- Retain existing SID validation and nonempty 4,096-byte token limit. Provision both fields in
  the encrypted payload under `account_sid_auth_token`; service metadata stores the account SID
  and must match the decrypted credential. Twilio has no Telnyx verification public key.
- Reuse the trusted protected-input CLI, credential store, service port and existing encryption.
  Live REST/webhook/media readers remain pending. Identity tests stay uncommitted until their
  own implementation checkpoint passes.

## Red-green verification

- Added four storage tests and one CLI case before implementation. The expected red run had
  four failures: valid Twilio provisioning returned invalid_provider_auth. The malformed-input
  control and existing CLI tests passed (10 total tests).
- Reused existing validation/storage paths. Twilio credentials use exactly two encrypted fields;
  service registration and resolution require account equality. The migration permits nil public
  keys only for Twilio while retaining Telnyx's key requirement and the credential ownership FK.
- The old FK test changed provider to Google; the new provider/public-key constraint rejected it
  first. Changed that fixture to a valid Twilio metadata shape so the test continues to exercise
  the credential provider ownership FK. Seventeen focused checks now pass, including Telnyx cases.
- No provider env variable is added: third-party credentials belong in the tenant DB. The CLI help,
  provisioning docs and service metadata examples document the existing Twilio auth shape.

## Independent review

- Calls 84 and Persistence 128 tests pass (11 excluded). The Persistence command selects all
  checkpoint tests except the separate, uncommitted identity red-test file; that file will ship
  only with its own passing implementation. No production behavior was excluded from this review.
- Independent review found that invalid UTF-8 token bytes could pass the new nonempty-binary
  validation and raise from JSON encoding. Added a malformed binary case before the fix; its
  expected red raised `invalid_byte, 255`. Added a valid Unicode/whitespace control too.
- ProviderAuth now checks String.valid? before storage. Valid UTF-8 token bytes remain exact;
  there is no trimming or additional ASCII-only policy. The 18-test focused group passes.
- Final Persistence checkpoint suite: 129 tests, zero failures, 11 excluded. Calls: 84 tests,
  zero failures. Format, warnings-as-errors compilation, strict Credo and unused-lock gates pass.
  Independent final review found no code blocker; corrected the stale progress counts and current
  umbrella-failure claim in the index/ledger. Full umbrella verification follows the identity slice.
