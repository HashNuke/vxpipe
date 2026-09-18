# Provider credential validation

Provider credential validation is a Console-triggered, Calls-owned workflow. It proves that the
submitted authentication material can access one bounded provider endpoint before Persistence
encrypts and stores that exact material. It does not prove that every model, voice, phone number,
region or later call is available.

## Boundary and ordering

1. Calls validates the provider, authentication kind and payload shape locally.
2. A `ProviderCredentialValidator` adapter performs one bounded upstream request.
3. Only an upstream success obtains a `last_validated_at` timestamp.
4. Persistence encrypts the submitted payload and writes that timestamp with the same credential
   version. A rejected or unavailable check never creates or replaces a credential.
5. Metadata reads may return `last_validated_at`, secret hints and lifecycle fields, but never the
   encrypted payload or raw authentication values.

The ordinary provisioning API remains available for trusted migration and local tooling and leaves
`last_validated_at` empty. Operator Console writes use the validated workflow. Replacing credential
material requires a fresh validation and writes new evidence; validation evidence is not copied
between versions.

## Provider probes

The production Console adapter performs read-only, non-inference requests with retries and redirects
disabled and a bounded receive timeout:

| Provider | Probe | Authentication |
| --- | --- | --- |
| Google AI Studio | `GET https://generativelanguage.googleapis.com/v1beta/models?pageSize=1` | `x-goog-api-key` |
| Deepgram | `GET https://api.deepgram.com/v1/projects` | `Authorization: Token …` |
| Zenmux | `GET https://zenmux.ai/api/v1/models` | `Authorization: Bearer …` |
| Telnyx | `GET https://api.telnyx.com/v2/call_control_applications?page[size]=1` | `Authorization: Bearer …` |
| Twilio | `GET https://api.twilio.com/2010-04-01/Accounts/{AccountSid}.json` | HTTP Basic |

These choices follow the providers' official model/project/account APIs: [Google models](https://ai.google.dev/api/models),
[Deepgram projects](https://developers.deepgram.com/reference/manage/projects/list),
[Zenmux API overview](https://zenmux.ai/docs/api/overview.html),
[Telnyx API overview](https://developers.telnyx.com/api/), and
[Twilio accounts](https://www.twilio.com/docs/iam/api/account).

HTTP 2xx means validated. Authentication and permission 4xx responses are rejected credentials,
except timeout/rate-limit statuses, which are temporary validation unavailability. Transport and 5xx
failures are also temporary unavailability. Response bodies are ignored so provider diagnostics do
not become a path for secret or account-data disclosure.

## Testing and operations

Default tests inject controlled validator and HTTP adapters. They verify request method, path and
authentication placement without reaching provider networks. Real-provider interoperability belongs
in an explicitly tagged integration lane and requires operator-supplied credentials. A stored
timestamp is historical evidence, not a reason to suppress a requested validation of replacement
material or to claim a later call will succeed.
