# Provider voice catalog and picker

## Scope and status

This is a proposed backend contract with a working Console/Storybook prototype.
The TypeScript boundary is `assets/src/admin/voiceCatalog.ts`; the picker consumes
that boundary without provider branches. Storybook injects a fixture client into
the existing call-spec page and provides dedicated voice-picker stories. Production
continues to use the existing voice field until authenticated endpoints and adapters
are implemented. No live provider calls or credentials are used by the prototype.

## Findings (2026-10-11)

| Installed provider | Source and retrieval | Filtering implications |
| --- | --- | --- |
| Cartesia TTS | Authenticated `/voices`; ID, name, description, language, gender, accents and account ownership; cursor pagination | Native search, language/locale, gender, ownership and archived flag. Request preview URLs explicitly when needed. [API](https://docs.cartesia.ai/api-reference/voices/list) |
| ElevenLabs TTS | Authenticated `/v2/voices`; IDs, names, labels, category, previews; page token | Native search, category, voice type, gender, age, languages, accent, use cases and other account/library filters. Language and use-case inputs can contain multiple values. [API](https://elevenlabs.io/docs/api-reference/voices/search) |
| Rime TTS | Public `voice_details.json`; speaker, modelId, language, gender, age, dialect, styles and other metadata | Fetch the complete catalog; constrain by installed model, then filter supported metadata in the adapter. The same speaker can occur for multiple models. [API](https://docs.rime.ai/api-reference/data/voice-details) |
| Deepgram Flux TTS | Published Flux voice inventory includes names, accents, age, character and use cases | A versioned adapter-owned inventory can filter those properties. No native Flux voice-list endpoint was established in this review. Preserve public `model: flux` + `options.voice`; the adapter constructs the wire model. [Inventory](https://developers.deepgram.com/docs/flux-tts/voices) |
| Google TTS | Installed adapter targets Gemini 3.1 Flash TTS with named prebuilt voices | Start with its model-specific prebuilt inventory. Current documentation additionally describes extended/custom voices for newer 3.8 models; do not expose those through the installed 3.1 adapter without verifying support. [Guide](https://ai.google.dev/gemini-api/docs/speech-generation) |
| OpenAI STS | Installed GPT-Live adapter accepts voice names | Keep a model-specific supported inventory. The Realtime guide lists named voices; do not reuse the separate TTS endpoint's inventory automatically. [Guide](https://developers.openai.com/api/docs/guides/realtime-conversations) |
| Morse | No selectable speaker identity in the installed model catalog | No voice picker. |

Provider metadata is descriptive, not universally filterable. No common gender,
accent, language or style vocabulary is imposed. Account-specific cloned voices
must be authorized in the same tenant/service context as the selected model.

## Contract

Keep `models/0` pure and cheap. Add a separate optional voice catalog adapter owned
by the installed speech implementation in Call Engine, resolved through the existing
provider registry. The speech session declares optional `voice_catalog/0`, returning
its provider catalog module or `:unsupported`; discovery never starts a speech session.
A proposed `Speech.VoiceCatalog` behavior has three callbacks:

```elixir
describe(model, context) :: {:ok, descriptor} | {:error, catalog_error}
list(model, query, context) :: {:ok, page} | {:error, catalog_error}
get(model, voice_id, context) :: {:ok, voice | nil} | {:error, catalog_error}
```

The context is supplied by Calls after authorization and effective-service binding
resolution. It contains capability, resolved credential/connection, request deadline
and a testable HTTP transport. It is never sent to the browser. Account-dependent
descriptors are allowed; a disconnected provider returns a typed credential error,
not another account's public catalog as an implicit fallback.

The browser client binds the tenant and effective service-binding context and exposes `describe(scope, signal)`,
`list(scope, query, signal)` and `get(scope, id, signal)`. Scope is
`{provider, capability, model}`. Only TTS and STS support this operation.

### Voice identity

```typescript
type Voice = {
  id: string;                 // exact selectable provider value
  name: string;               // readable display name; may equal id
  description?: string;
  attributes: { key: string; label: string; value: string }[];
};
```

- A name-only provider uses that exact name as its ID. Never generate slugs or
  assume names are unique when a provider gives a separate ID.
- IDs are unique within the scope/account. Deduplicate paginated rows by ID.
- Attributes are an allowlisted, display-ready projection. Missing metadata stays
  absent; never infer demographics, accents or compatibility from a name.
- The model descriptor's existing `voices.parameter` owns the write location:
  `options.voice`, `options.speaker`, etc. Store only the selected ID there. Names,
  filters and catalog responses are authoring data, not portable spec fields.
- Resolve a saved ID separately through `get`; absence from the first page is not
  evidence that it was deleted. On failure/missing voice, retain the ID and allow
  replacement. Merely opening or cancelling the picker never changes the source.

### Filters and pages

`describe` returns provider/model display names, whether search is supported and
an ordered `filters` array. Each filter has an opaque key, readable label and one
of `select`, `multi_select`, `text`, `boolean` or `number`. Selects carry value/label
pairs; text can carry a hint and numeric fields can carry bounds. Boolean filters
have three states: absent, true, false. Only advertised filters are accepted.

`list` takes `{search, filters, cursor}` and returns
`{voices, nextCursor, total?}`. Missing `total` means unknown, not zero. The server
bounds page size (initially 25, maximum 100), query lengths and filter counts.
Unknown keys, invalid values and out-of-range numbers produce typed errors.
Multi-value matching semantics belong to the adapter; ElevenLabs language matches
any requested language. Filters from different controls are combined with AND.

Descriptors must declare supported options from a provider schema, documented enum
or complete catalog. Do not derive dropdown choices from one loaded page. If a
provider accepts an open vocabulary, expose text input or add a future remote
facet-suggestion contract; do not pretend a short hardcoded list is exhaustive.
The Storybook option lists are deliberately small fixture datasets.

Native filtering/pagination is forwarded by the adapter. Local filtering is valid
only over a complete, bounded inventory, before pagination. Reject incomplete
fetches instead of presenting a partial set as all matching voices. Filter model
compatibility before returning rows. Return opaque, server-issued cursors scoped
to tenant, service binding, capability, model and query; reject reused/mismatched
cursors. Never use a provider-supplied next-page URL as an unrestricted fetch URL.

## Proposed HTTP and ownership

Calls owns authorization/service resolution and safe errors. Call Engine owns the
voice catalog behavior and provider mappings. Console/Gateway serialize the same
DTOs under their existing authorized tenant provider-catalog routes:

- `GET .../providers/:provider/voice-catalog?capability=...&model=...`
- `POST .../providers/:provider/voices/search` with scope, filters and cursor
- `GET .../providers/:provider/voices/:id?capability=...&model=...`

The browser never chooses credentials. Resolve the spec's effective binding on the
server, including existing credential-name overrides, before constructing the client
context. Bind it to the authorized spec/draft and selection path; a tenant-only
context cannot identify an overridden account correctly. Any opaque context reference
must be reauthorized for every call. Keep authoring permissions equivalent to existing model listings. Restrict
provider endpoints to adapter constants; apply connection/request timeouts, bound
responses, and redact upstream payloads in logs/errors. Suggested public error
codes: `unsupported_voice_catalog`, `invalid_voice_query`, `credential_unavailable`,
`provider_forbidden`, `rate_limited`, `catalog_unavailable`, `invalid_cursor`.
Include bounded retry hints for rate limits. Never retry automatically without bound.

Cache public inventories by provider/API version/model; cache private inventories
and `get` by tenant and effective binding revision as well. Invalidate on binding
changes and never share account-specific results across tenants. Bound cache lifetime
and size; do not cache failures as empty results. No cache TTL is an availability
guarantee when the provider can revoke a voice.

Audio audition is a separate follow-up: return an authorized same-origin preview
handle, not provider credentials or arbitrary remote URLs. Play only on user action,
stop the previous preview, and distinguish provider samples from chargeable synthesis.
This prototype intentionally has no nonfunctional play buttons.

## UI and alternatives

The inline field shows the readable name and a few properties, with a Change action.
The modal uses compact rows with metadata tags, secondary IDs and the current voice.
The title and provider/model share a header line when space permits. There is no
catalog count: a paginated or account-specific response need not provide a total.
All provider-declared select filters, including language, use a searchable dropdown.
The adapter still determines whether each filter accepts one value or several;
providers without a supported language filter do not show a fabricated one.

Search and filter edits are staged until **Apply filters** (or Enter in the search
field). Clear stages an empty query and also requires Apply. Inline feedback marks
unapplied changes, a pending request and successfully updated results. Applying
submits the complete query to `VoiceCatalogClient.list` and resets the cursor;
the picker never filters the currently loaded page itself. Storybook's fixture
client filters its complete sample inventory locally. This is not live provider
filtering; authenticated endpoints and adapters remain follow-up work below.

Voice selection is separately staged with Cancel / Use voice and survives filtering.
Abort and ignore stale requests. Loading/error/empty states preserve source.
Use existing shadcn dialogs, fields and radio groups; maintain light/dark themes and
keyboard operation. No recommendation badges are added.

Rejected: a universal fixed filter bar (claims unsupported filters); free-text IDs
as the primary chooser (unreadable); fetching from providers in the browser (leaks
credential responsibilities); loading entire large private catalogs into the model
bootstrap (slow/account-sensitive); filtering only a result page (incorrect matches);
changing the portable source to store display metadata (stale names and digest churn).

## Delivery and verification

- [x] Inspect installed adapters and official provider documentation.
- [x] Define the shared UI contract and proposed backend behavior/ownership.
- [x] Build generic filter-driven picker and fixture adapter; inject in Storybook page.
- [x] Test staged selection, ID-only writes, pagination/query reset, dynamic filters,
  stale response rejection, unavailable saved IDs, retry and read-only behavior.
- [x] Review desktop/mobile, filtering, empty states, call-spec integration and
  keyboard focus in Chrome; run completion checks. Frontend/build checks pass;
  umbrella tests are blocked by the existing Ortex native-load failure (see labnotes).
- [ ] Implement authenticated endpoints, adapter mapping and bounded cache.
- [ ] Add adapter fixture/contract tests, authorization/account-isolation tests,
  query validation/model-compatibility tests and an explicit live integration lane.
- [ ] Wire the production client and verify real account catalogs before release.

No milestone index exists at `docs/milestones/index.md` in this checkout. This design
records the proposed follow-up without claiming a backend milestone is implemented.
