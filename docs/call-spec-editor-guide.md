# Authoring call specs in Console

Sign in as an installation operator, open a tenant's **Call specs** page, then
choose **New call spec** or an existing spec's name. The Calls column opens that
spec's calls. The editor does not start test calls. New specs receive a server-generated public
UUID. The ID is not editable; saves append revisions under that same ID.

The canvas shows participants and transfer destinations. Select a participant to
edit its fields; **Call settings** opens direction, defaults, variables and call
policies. On a phone, these controls open in a side sheet. Model and voice choices
come from the installed provider catalog. Choosing a provider selects its
recommended model and voice. Existing saved selections are preserved. A public
speech model such as `flux` and its `options.voice` remain separate in the source;
the provider adapter composes its concrete model ID.

**Save draft** creates the first immutable revision or appends a revision to the
same spec. It does not change which revision is published. **Publish** publishes
the saved revision and is available only when the draft has no unsaved edits.
The header shows the open and published revision numbers. Editing while a save is
in progress retains the later changes as unsaved; publishing waits for another save.

Validation messages appear beside the affected fields and in the issues drawer.
A blocked save explains the first issue; **Show** opens its participant and tab.
The backend independently validates every save and publish. Credential or service
failures link to the tenant's Services page. A failed request keeps the current
source; **Retry** uses the current draft. A conflict offers to reload the latest
saved revision after confirming that unsaved changes can be discarded.

**View JSON** lets you inspect, copy or download the portable source. The graph is
a projection of that source, so a no-op save preserves its meaning and digest.
Large integer values in enums, schema bounds and provider options retain their
exact digits when edited, saved or exported. They remain JSON numbers.
The editor does not store canvas positions or silently migrate older schemas.
Sources using schema `20260915.01` open read-only.

Add `?revision=N` to an existing spec's URL to inspect that immutable revision.
**Continue editing latest revision** opens the current source. This does not copy
an older revision over newer work. Browser Back/Forward and in-app departures ask
before discarding edits or an in-flight write. Reloading or closing the document
uses the browser's own unsaved-changes confirmation. If a session expires during
a write, the editor keeps the source in the tab and disables authoring; copy or
download it before leaving to sign in again.

## Operator API

These endpoints require the existing installation-operator session. Writes also
require the Console CSRF token. Responses are private and not cached.

| Method and path under `/admin/api/tenants/:tenant_key` | Result |
| --- | --- |
| `GET /call-specs/:id` | Latest saved source and revision/publication metadata |
| `GET /call-specs/:id?revision=N` | Requested immutable revision and current publication metadata |
| `POST /call-specs` with `{ "source": ... }` | New spec, revision 1 |
| `PUT /call-specs/:id` with `{ "source": ... }` | Append an immutable revision |
| `POST /call-specs/:id/revisions/:revision/publish` with `{}` | Publish the specified saved revision |
| `GET /call-spec-editor-lookups` | Effective credential names, telephony services and MCP integration names |
| `GET /providers?capability=...` | Installed providers and credential availability |
| `GET /providers/:provider/models?capability=...` | Public models, recommended defaults and voice descriptors |

Read/write responses wrap a `call_spec` object. It includes `call_spec_id`,
`revision`, `schema_version`, `source`, `source_digest`, `published`,
`published_at`, `validation_errors` and participant `routes`. Reads additionally
include `latest_revision` and `published_revision`. Error responses use
`{ "error": { "code": ..., "path": [...], "reason": ... } }` when a field path
and safe reason are available. Another tenant's spec ID is not found. Lookups
never return credential values or perform remote MCP tool discovery; MCP tool
names remain explicit text fields.
