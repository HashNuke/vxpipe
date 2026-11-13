# Alphanumeric tenant keys

## Contract and implementation

- Tenant keys are generated in application code by `Vxpipe.Calls.PublicId.tenant_key/0`; PostgreSQL stores the key supplied by the application. Browser creation, administration/bootstrap and demo setup share this generator.
- New keys retain the existing 16-character format but use only ASCII letters and digits. The generator discards the two Base64 symbols and replenishes from cryptographic randomness until enough accepted characters are available. This avoids truncating a filtered key to fewer than 16 characters or introducing modulo bias.
- Existing-key validation and database records remain compatible with older keys containing `-` or `_`. API-key, join-token and UUID generators are unchanged.
- Updated the Onboarding Storybook demo tenant and newly created fixture keys to reflect the alphanumeric format. Existing unrelated fixtures remain compatibility examples.
- Added the format contract to the HTTP API documentation.

## Verification

- Red: the tenant-creation boundary test failed on a generated key containing hyphens.
- Green: 11 focused tenant creation, administration and demo setup tests passed. The new contract is checked across 64 creations.
- Umbrella formatting, warnings-as-errors compilation and strict Credo passed. The full umbrella suite completed: the Calls suite passed all 374 tests; two unrelated tests failed (a context-compactor acknowledgement timeout and room registry cleanup). Both passed with `mix test --failed` without code changes.
- The concurrent Console preview changes passed all 54 relevant frontend tests, Console TypeScript, changed-file ESLint and desktop/mobile browser inspection.
- Unused-dependency and final diff checks passed.
