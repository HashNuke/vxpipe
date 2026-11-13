# Provider voice picker

Research and implementation contract, 2026-11-13. Progress belongs in
[the milestone](../../labnotes/milestones/provider-voice-picker.md).

## Decision

Connect the existing shared voice picker to authorized backend catalogs. Keep
one interface for opening audio, default capabilities, and participant TTS/STS
selections. Provider differences belong in catalog adapters, not separate dialogs.
Call specs continue to store provider, model, credential name and the selected
voice identifier in the adapter's existing option (`voice`, or Rime's `speaker`).

This is authoring functionality. Catalog requests must not run during call
startup, speech generation, saving, or publishing. Upstream catalog availability
must not become a new dependency for running an already saved call spec.

## Existing implementation and reuse audit

The pre-implementation audit covered application Elixir code, Console TypeScript, integration
manifests, and existing provider milestones. No production provider voice-list,
search or single-voice lookup implementation was found. There is useful existing
code on both sides of the missing HTTP boundary:

| Existing code | Reuse and gap |
| --- | --- |
| `assets/src/admin/voiceCatalog.ts` in Console | `describe/list/get`, descriptors, filter types, cursor pages and voice records already define the UI boundary. Credential identity has now been added. |
| `callSpecEditor/voice-field.tsx`, `voice-picker.tsx`, `voice-filters.tsx`, `voice-filter-select.tsx` | Shared modal, explicit search/filter application, pagination, cancellation, retries, unknown saved IDs and focus return. Reuse these components. |
| `VoicePicker.stories.tsx`, `voiceCatalogFixtures.ts` | Cartesia, ElevenLabs, Google, OpenAI names-only, Deepgram and Rime examples, plus loading/error/unavailable/light states. Data is illustrative, not production availability. |
| `callSpecEditor/capability-fields.tsx` | Already uses the picker when `VoiceCatalogContext` is supplied; previously rendered a text field or select without context. Production `CallSpecEditorRoute.tsx` now supplies that context; the manual fallback has been removed. This is the single voice-control replacement point found in the application. |
| `Vxpipe.CallEngine.ModelCatalog`, `Speech.Model`, speech adapters' `models/0` | Existing model IDs, default voices, voice option names and installed-capability resolution. Most voices are `Model.free_voice(default)` descriptors, not catalogs. MorseCode API already has a finite list. |
| `Vxpipe.Calls.ProviderCatalog`, `CallSpecEditorLookups`, `EffectiveServiceBindings` | Tenant authorization, accessible platform bindings, credential availability and public binding names. Reuse their policy and credential resolution; the current model endpoints do not fetch voices. |
| MorseCode API restart probe | A test fixture requests `/v1/voices` to check origin replacement. It is not a reusable production listing/search client. |

Paths above are relative to `apps/vxpipe_console/` where abbreviated. Speech
adapters live under `apps/vxpipe_call_engine/lib/vxpipe/providers/`; credential
contracts live in `apps/vxpipe_providers/`. Do not create a new provider subsystem
because the latter application does not contain the speech adapters.

## Provider findings

Only offer choices compatible with the models and wire formats currently
implemented. Catalog metadata is not evidence of synthesis compatibility.

| Provider / capability | Existing adapter | Catalog source and remaining work |
| --- | --- | --- |
| Cartesia TTS | Sonic model descriptors; default UUID; `options.voice` | Authenticated paged list/get against `/voices`. Map `q`, ownership, language and gender filters, pin the supported version header, and normalize cursor results. Use the selected connection's key. [List](https://docs.cartesia.ai/api-reference/voices/list), [get](https://docs.cartesia.ai/api-reference/voices/get). |
| ElevenLabs TTS | Flash 2.5 / Multilingual v2 descriptors; default George ID; `options.voice` | Account-scoped `/v2/voices` search/filter/pagination and ID lookup. Preserve IDs, names and useful labels only; do not expose the upstream record's unrelated sharing/account data. [List/search](https://elevenlabs.io/docs/api-reference/voices/search), [get](https://elevenlabs.io/docs/api-reference/voices/get). |
| ElevenLabs STS | Mini/Max accept a voice string; default `brian` | Use account voice IDs unchanged from `/v2/voices`, plus direct lookup of the documented `brian` default. The official Realtime library support and string schema resolve the initial compatibility question; evidence and inference are recorded below. No name-derived slugs. |
| Deepgram TTS | Public `flux` model; `model_for_voice/1` emits `flux-<voice>-en` | Normalize the TTS portion of [model metadata](https://developers.deepgram.com/guides/fundamentals/model-metadata), restricted to supported Flux English voices. The [Flux voice reference](https://developers.deepgram.com/docs/flux-tts/voices) also lists other languages; the existing wire mapping cannot select those. Confirm Flux coverage in the metadata response; a documented bundled Flux list is acceptable if absent. Do not expose Aura as Flux. |
| Google TTS / STS | Installed TTS is `gemini-3.1-flash-tts-preview`; STS is `gemini-3.8-live`; both use prebuilt voice names | Supply documented prebuilt lists, explicitly scoped to capability/model. Current [speech-generation docs](https://ai.google.dev/gemini-api/docs/speech-generation) describe additional library/designed voices for newer TTS models; that does not make them supported by our installed adapter. [Live capability docs](https://ai.google.dev/gemini-api/docs/live-guide) use `prebuiltVoiceConfig`. Verify the installed TTS model's supported set rather than copying a newer model's full catalog. |
| OpenAI STS | GPT-Live accepts a string, defaults to `marin`, and transmits that string | Reuse the built-in voice names documented by the [Live session API](https://developers.openai.com/api/reference/resources/live/methods/create). [Custom voices](https://developers.openai.com/api/docs/guides/custom-voices) require an `{id}` wire value, which our adapter does not emit. Do not offer them in this slice or pass their IDs as named voices. |
| Rime TTS | Coda; `options.speaker`; no language option | Use the public names-by-model/language and metadata catalogs linked from [Rime voices](https://docs.rime.ai/docs/voices.md). Search/filter locally over a bounded normalized public list. Initially offer only speakers compatible with the adapter's default language; adding a language option is separate runtime work. |
| Morse local / MorseCode API | Local speech providers and API's finite `morse` voice | Reuse actual model descriptors. A capability with no voice parameter needs no control. The API's single supported voice can use the same picker without a remote discovery request. |

No paid calls, audio generation, account mutations, or provider credential reads
were performed for this research. Provider docs are evidence of available APIs;
authenticated response compatibility still needs fixture-based implementation
checks and, if explicitly authorized, narrowly scoped read-only interoperability.

## Resolved provider evidence (2026-11-13)

- **ElevenLabs Realtime:** the [official launch announcement](https://elevenlabs.io/blog/realtime)
  explicitly says Mini and Max support the voice library, and the
  [model reference](https://elevenlabs.io/docs/overview/models) describes library
  voice customization. The [voice concepts](https://elevenlabs.io/docs/overview/intro)
  identify voices by API ID. The public [OpenAPI schema](https://api.elevenlabs.io/openapi.json)
  defines `OpenAIAudioOutputConfig-Input.voice` as a string, default `brian`, with
  no enum or alternative voice-discovery endpoint. Taken together, these support
  sending the account catalog's exact `voice_id` as the Realtime voice string.
  This is an inference from those official contracts, verified against our wire
  serializer for both models; it is **not** an authenticated upstream session test.
  `/v2/voices` is shared for discovery only. No TTS tuning filter is imposed on
  Realtime, and display names are never converted to aliases.
- **Deepgram:** the public [model response](https://api.deepgram.com/v1/models)
  contained 103 TTS entries and no Flux entries during research. Use the 36
  English names in the [Flux voice reference](https://developers.deepgram.com/docs/flux-tts/voices),
  preserving the installed `flux-<voice>-en` mapping. Aura and other languages are
  excluded. Updating this bundled list is a normal provider metadata change.
- **Google:** the installed [3.1 Flash TTS model](https://aistudio.google.com/docs/models/gemini-3.1-flash-tts-preview)
  uses the 30 prebuilt names in the [speech guide](https://aistudio.google.com/docs/speech-generation).
  The [Live capability guide](https://aistudio.google.com/docs/live-api/capabilities)
  uses those prebuilt voices through `prebuiltVoiceConfig`. Both installed models
  get that bounded set; newer designed/library voices are excluded.
- **OpenAI:** the [Live session schema](https://developers.openai.com/api/reference/resources/live/methods/create)
  lists 38 named voices. Offer those string values for `gpt-live-1`, excluding
  custom `{id}` values. Tests check every named choice through the existing parser
  and session serializer; no synthesis request is made.
- **Rime:** [voice metadata](https://docs.rime.ai/api-reference/data/voice-details.md)
  includes speaker, model and language in one public array. The
  [public catalog](https://users.rime.ai/data/voices/voice_details.json) had 654
  rows when researched. Filter `modelId=coda` and `lang=eng`; no second names
  request or credential forwarding is needed. A 5,000-row/2 MiB bound protects
  the local search. Saved IDs are found in this complete bounded list.
- **Cartesia:** the [list contract](https://docs.cartesia.ai/api-reference/voices/list)
  uses `starting_after` with the returned `next_page` ID, not a URL. Reuse the
  installed adapter's version header, require active voices with UUIDs accepted
  by its option parser, and expose language, gender and ownership filters.
- **ElevenLabs TTS:** use Flash 2.5 and Multilingual v2 model descriptors already
  installed. Professional voices with explicit tuning states must be fine-tuned
  for the chosen model. `high_quality_base_model_ids` describes a recommendation,
  not an exclusion rule. Optional names fall back to the exact ID. Storybook
  advertises only the filters implemented by the backend.

These checks resolved the initial research gates. They reuse model parsers and
pure wire serializers, plus synthetic HTTP responses. Public documentation and
public metadata were read; no private account catalog or paid speech request was
made. Authenticated provider interoperability remains optional and requires
explicit authorization.

## Backend boundary

1. Add a small voice-catalog contract beside the existing speech catalog in Call
   Engine. Reuse `Registry.resolve_capability/2`, adapter model metadata and the
   existing HTTP dependency. Keep provider HTTP/normalization code beside its
   adapter; reuse finite model voice lists without network access.
2. Add an authorized Calls workflow for descriptor, list and ID lookup. It
   validates tenant access (`call_specs.read`), supported provider/model/capability,
   and the selected effective credential before calling the catalog adapter.
   A tenant override wins under the existing resolution rules. Platform-only
   bindings remain unavailable without the existing platform authoring permission.
3. Console exposes thin authenticated routes under the existing tenant editor
   API namespace. Provider keys stay server-side. Local credential-free providers
   still require tenant authoring access, but not a provider credential.
4. The production `VoiceCatalogClient` implements the existing three operations
   using those routes and supplies the shared context to the editor. Include the
   selected `credential_name` in scope. Resolve inherited defaults before sending
   the request; do not silently browse the provider's default account.

The public contract stays compact: descriptor, a page of `{id, name, description?,
attributes}`, `nextCursor`, optional total, and a single-voice result or absence.
Only advertised filter keys/types are accepted. Use bounded query/cursor lengths,
page size (at most 100), response size (2 MiB), and upstream timeouts (8 seconds receiving, 3 seconds connecting). Never follow a
provider pagination URL supplied by the browser. Return stable sanitized failures
for missing connection, forbidden access, rate limit, unavailable upstream and
invalid response; do not turn a network failure into an empty catalog.

`get` must resolve an ID outside the first list page without crawling every page.
Use the provider's ID endpoint, ID filter, or the complete bounded static catalog.
An inaccessible/deleted saved voice remains visibly identified by its stored ID;
opening a dialog, failed lookup or refreshing a list must not change the source.

## UI behavior and request lifecycle

Reuse the reviewed layout and controls. Replace the production text-input branch
once the catalog is wired. Do not keep a legacy manual-entry mode or a second
provider-specific modal. Unknown saved IDs remain readable and can be replaced
through the picker; selecting a voice stores its ID, not its display name.

Reset results, filters and pagination and cancel obsolete requests when tenant,
provider, model, capability or credential changes. Include the same scope in
resolved-voice identities: the `VoiceField` identity includes credentials.
Late results must not populate a new connection's dialog. Disconnect or permission
loss must prevent subsequent catalog access even if the UI has an earlier result.

Scope covers opening audio, call-wide defaults and participant overrides,
including LLM-backed TTS, native STS and the new-spec editor after creation.
Selection must preserve unrelated options and explicit credentials, support
inherited selections, survive save/reload, and leave Publish usable for valid
edits. Catalog errors stay inside the picker, with retry and cancellation.

## Performance and scope limits

Fetch the selected voice's details for display and fetch pages when the picker
opens or the user applies filters/loads more. Do not eagerly download every
provider's voices with the model catalog. Reuse results within the mounted editor
using its existing cancellation/request patterns. The dialog keeps at most 20
pages (at most 2,000 rows given the 100-row response limit), stops repeated
cursors, and asks the author to refine the search when that limit is reached.
A new search resets the page budget. Keep public static catalogs
bounded; search them locally on the backend.

Start without a database catalog, periodic jobs, distributed cache, a new OTP
process tree, or an SDK dependency. They are not required to make this picker
work. If measured request volume later justifies shared caching, authorize every
request first and isolate private data by tenant, effective connection identity
and credential revision as well as provider/model/capability/query. A provider-only
cache key would leak or mix account-specific voices.

Voice previews, synthesis, cloning/design, new speech models, custom OpenAI wire
formats and expanded language support are outside this slice. Existing supported
private TTS voices are inside scope. The UI must not advertise unsupported voices
just because another API from the same provider lists them.

## Verification and design review

Local review checked ownership/dependency direction, credential scope, selected-ID
round trips, all shared form sites, stale requests, provider compatibility and
bounded loading. The main corrections from the audit are the missing credential
in `VoiceScope`, separate ElevenLabs STS compatibility, English-only Flux mapping,
and OpenAI custom-voice wire mismatch. These are implementation gates, not reasons
to rebuild the existing picker.

The adjacent editor repair filters on existing `credential_available`, attaches
the opening-audio binding and lets Publish save a valid draft before publishing
its exact revision. Its focused test/browser evidence is in
[the checkpoint labnote](../../labnotes/20261113-1413-opening-audio-editor.md).
Those repairs do not complete the production voice-catalog milestone.
