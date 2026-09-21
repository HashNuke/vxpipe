# Provider credential testing and storage

Credential testing and credential storage are separate operator actions. Testing answers whether
the submitted authentication material can access one bounded provider endpoint now. Saving checks
the local credential shape, encrypts it and persists it without making an upstream request. Neither
action proves that every model, voice, phone number, region or later call is available.

## Operator API contract

The Console exposes the same actions at platform and tenant scope:

| Action | Platform endpoint | Tenant endpoint |
| --- | --- | --- |
| Test | `POST /admin/api/platform/credentials/test` | `POST /admin/api/tenants/:tenant_key/credentials/test` |
| Create | `POST /admin/api/platform/credentials` | `POST /admin/api/tenants/:tenant_key/credentials` |
| Replace | `PATCH /admin/api/platform/credentials/:credential_id` | `PATCH /admin/api/tenants/:tenant_key/credentials/:credential_id` |

All endpoints require the installation-operator session and CSRF token. They accept the provider,
optional binding name and provider-specific `values` map. Raw values are filtered from request logs
and never returned.

The test endpoints are read-only:

- `200 {"status":"valid"}` means the bounded upstream request accepted the credentials.
- `422 credential_rejected` means the provider rejected them.
- `422 invalid_credential` means the local provider, binding name or payload shape is invalid.
- `501 credential_validation_unsupported` means Vxpipe has no safe probe for that provider/auth kind.
- `503 credential_validation_unavailable` means the provider or network could not complete the test.

An unsupported, rejected or unavailable test does not disable **Save**. Saving still applies the
provider/auth schema and storage rules. A successful test does not save anything, and create/replace
does not run the provider probe. The Console keeps the entered values after a test so the operator
can correct or save the same draft; changing a field clears the displayed test result.

`Vxpipe.Calls.validate_operator_credential/7` owns the test boundary. It checks installation
authority, resolves the provider/auth binding, validates the payload shape, and calls the configured
`ProviderCredentialValidator`. The ordinary create and replace functions own persistence. This
keeps provider availability out of the encrypted-storage transaction and allows providers without a
safe validation operation to be configured deliberately.

New tests and saves do not write `last_validated_at`. Existing non-null values are retained as
historical metadata from the earlier coupled workflow; they are not evidence that the current
credential version was tested by this contract.

## Provider-owned modules

Provider-specific knowledge lives under a provider directory in the umbrella child that owns the
integration. The `vxpipe_providers` child owns manifests, credential schemas and pure credential
test-request descriptions. Deepgram's speech sessions and sockets use the
`Vxpipe.Providers.Deepgram` namespace while compiling in CallEngine. Telnyx's signed webhook,
media socket, telephony profile and HTTP handlers use `Vxpipe.Providers.Telnyx` while compiling in
Gateway. Google AI Studio's credential schema and probe use `Vxpipe.Providers.Google`; its model
inference continues through shared ReqLLM. Rime's credential shape and probe use
`Vxpipe.Providers.Rime`. Console executes these declared probes. Other provider
integrations retain their existing
names until migrated. The
[provider-package milestone](milestones/provider-integration-packages.md) tracks that progression.

This is the current lightweight provider-package boundary. Adding a provider means adding its local
credential schema, optional credential-test module, and only the runtime adapters it actually
supports. A provider without a credential-test module reports unsupported while its declared
credential schema can still be saved. Keeping these directories inside their owning umbrella child
also preserves dependency direction: a Console-only probe does not make Calls or the call engine
depend on Console, and a telephony SDK does not become a dependency of unrelated speech code.

## Provider probes

The production Console adapter performs bounded authentication requests with retries and redirects
disabled and a ten-second receive timeout:

| Provider | Probe | Authentication |
| --- | --- | --- |
| Google AI Studio | `GET https://generativelanguage.googleapis.com/v1beta/models?pageSize=1` | `x-goog-api-key` |
| Deepgram | `GET https://api.deepgram.com/v1/projects` | `Authorization: Token …` |
| Zenmux | `GET https://zenmux.ai/api/v1/models` | `Authorization: Bearer …` |
| Rime | `POST https://users.rime.ai/oov` with a harmless `hello` lookup | `Authorization: Bearer …` |
| Telnyx | `GET https://api.telnyx.com/v2/call_control_applications?page[size]=1` | `Authorization: Bearer …` |
| Twilio | `GET https://api.twilio.com/2010-04-01/Accounts/{AccountSid}.json` | HTTP Basic |

The Telnyx test uses only the API key. Its optional webhook-signing public key is locally validated
and stored, but it is not authentication material for the Telnyx API request.

These choices follow the providers' official model/project/account APIs: [Google models](https://ai.google.dev/api/models),
[Deepgram projects](https://developers.deepgram.com/reference/manage/projects/list),
[Zenmux API overview](https://zenmux.ai/docs/api/overview.html),
[Rime API-key documentation](https://docs.rime.ai/docs/lovable),
[Telnyx API overview](https://developers.telnyx.com/api/), and
[Twilio accounts](https://www.twilio.com/docs/iam/api/account).

HTTP 2xx means accepted. Authentication and permission 4xx responses mean rejected credentials,
except timeout and rate-limit statuses, which mean temporary unavailability. Transport and 5xx
failures also mean temporary unavailability. Response bodies are ignored so provider diagnostics do
not become a path for secret or account-data disclosure. Provider/auth combinations without an
explicit request clause return unsupported and perform no network request.

## Verification

Default tests inject controlled validator and HTTP adapters. They verify the request method, path,
authentication placement, read-only behavior, authorization, CSRF protection and the absence of
persistence. Real-provider interoperability belongs in an explicitly tagged integration lane and
requires operator-supplied credentials.
