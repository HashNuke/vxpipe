# Console credential management

Status: implemented for the existing Google, Deepgram, Zenmux, Rime, Telnyx and Twilio credential
contracts. Optional provider testing is implemented as a separate read-only action.

## Decision

The installation-operator Console owns provider selection and provider-specific input fields, while
Calls owns authorization, closed credential-shape validation and credential identity. Console does
not accept a credential name: new records use the provider key as their binding name. Existing
named records remain readable and can be replaced by stable credential ID.

Credential replacement is an explicit CSRF-protected operation scoped by tenant, credential ID and
provider. Persistence locks the exact row, encrypts the complete replacement payload with a new
credential version and preserves the public credential ID. It never returns the payload.

The Services inventory lists active stored credentials only. Provider names are presentation
labels; internal binding names and telephony registration names are not used as service titles.
Responses contain a bounded `credential_preview` made from non-secret hints:

- API keys and Twilio Account SIDs expose four leading mask characters plus their saved last four.
- Twilio Auth Tokens are represented by a fixed six-character mask and have no stored suffix.
- credentials created before the hint migration remain fully masked until replaced.

The last-four hints are derived during create/replace and stored separately from encrypted payloads.
Each provider credential module declares the ordered preview fields and whether each field is
last-four or fully masked. The Console does not choose preview fields from the auth kind. Unknown
provider metadata yields no preview. The optional Telnyx public key is omitted from inventory
previews. Provider-specific Console field components own the visible inputs; providers with identical
API-key inputs share one component. A common shell retains the existing Test, Save, validation,
secret clearing, and status behavior. An unrecognized stored provider shows no generic credential
input and disables Test and Save. This preserves metadata-only inventory reads and avoids
decrypting every credential to render the page. Raw credentials remain filtered from request logs
and are cleared from browser form state after terminal submissions.

## Rejected alternatives

- Decrypting credentials during every inventory read was rejected because the page only needs a
  non-secret hint and should retain its metadata-only read boundary.
- Returning encrypted payloads or deriving previews in React was rejected because neither creates
  a trustworthy or safe secret-read contract.
- Updating by provider/name alone was rejected because old installations can contain multiple
  named bindings; the stable public credential ID identifies the row while tenant/provider checks
  prevent cross-binding replacement.
- Rendering raw credential values or configuring an unrestricted preview mode was rejected; only
  fixed masking and last-four modes are supported.

## Implications

The database migration adds a non-null `secret_hints` map with an empty default for old rows.
Operators should run migrations before deploying the matching Console build. Replacement increments
the encrypted credential version, so ciphertext remains bound to the exact current identity.

Saving does not claim upstream validity and does not set `last_validated_at`. The separate
**Test credentials** action uses provider-owned bounded requests, never persists, and leaves
**Save** available when a safe provider probe is unsupported. See the
[credential testing and storage contract](provider-credential-validation.md).
