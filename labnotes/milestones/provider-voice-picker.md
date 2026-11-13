# Provider voice picker

Status: provider coverage and production wiring are implemented on main. Final
shared-behavior and browser acceptance checks are in progress.

## Outcome and prerequisites

An author selects a configured provider/model, opens the existing voice modal,
searches or filters supported voices, selects one and saves/publishes the call
spec. The same component serves opening audio, defaults and participant TTS/STS
through tenant and installation-operator editor routes.

Read the [research and design](../../docs/design/provider-voice-picker.md),
[call-spec editor](call-spec-editor.md),
[provider credentials](tenant-provider-credentials-and-platform-configuration.md),
[provider packages](provider-integration-packages.md), and
[ElevenLabs Realtime](elevenlabs-realtime-models.md) first. Existing effective
binding authorization and the adjacent configured-provider/Publish repair are
prerequisites. Packaging, call retention and guardrails are not prerequisites.

## Contracts

- Reuse `VoiceCatalogClient`, `VoiceField`, `VoicePicker`, filters and provider
  stories. Provider behavior lives behind one shared API, not separate modals.
- Voice scope includes tenant, capability, provider, model and selected effective
  credential. Follow existing platform permissions and tenant override rules.
- Show only voices accepted by the installed adapter's model and wire format.
  Keep existing voice identifiers and `voice`/`speaker` parameter names.
- Preserve unknown saved IDs and unrelated options. Catalog requests never edit
  a source document or run on the call startup/save/publish path.
- Fetch catalogs on demand with bounded requests; no database cache, background
  jobs, per-voice processes, new SDK or paid preview generation is required.
- Remove the production free-text voice fallback when wiring is complete.
  The JSON source editor remains the existing advanced source editor.

## Implementation checkpoints

### A — Authorized backend and one working provider

- [x] Define the small catalog adapter boundary beside the existing speech
  catalog, normalize the existing UI contract, and reuse finite model voice lists.
- [x] Add the Calls authorization/credential-resolution workflow and thin Console
  descriptor/list/get routes. Cover tenant-only, authorized platform inheritance,
  tenant override, missing/disconnected credentials, forbidden access and sanitized
  upstream failures with focused offline boundary tests.
- [x] Implement ElevenLabs TTS listing/search, filters, cursor paging and direct
  saved-ID lookup using the selected credential. Use captured/synthetic HTTP
  fixtures with no live account calls; filter incompatible model voices.
- [x] Wire the production client/context and credential-aware scope into all shared
  voice fields. Verify an ElevenLabs selection through opening audio, defaults and
  a participant, including save/reload and Publish from a dirty draft. This is the
  first runnable vertical slice.

### B — Complete the existing provider coverage

- [x] Add Cartesia authenticated list/search/get and Rime public catalog
  normalization. Keep supported model/language constraints and real filter
  capabilities; replace illustrative Storybook filter assumptions where necessary.
- [x] Add Deepgram Flux English voices from metadata, verifying the metadata
  actually includes Flux; use a documented bundled list if it does not. Reuse
  public-to-wire voice mapping and exclude unsupported model/language combinations.
- [x] Supply model-specific Google prebuilt and OpenAI GPT-Live named-voice lists
  plus existing finite Morse descriptors. Verify every offered choice passes the
  existing public option parser and serializes into the supported wire shape.
- [x] Resolve ElevenLabs Realtime voice compatibility using official API/schema
  evidence, then provide Mini/Max catalogs. Do not assume `/v2/voices` TTS IDs or
  name-derived slugs are valid. Record any remaining provider documentation gap
  explicitly instead of claiming all-provider completion.

### C — Complete shared behavior and acceptance

- [ ] Finish cancellation, scope changes, selected-ID lookup, empty/error/retry
  states, pagination bounds and unknown saved voice preservation. Remove manual
  voice inputs from production capability fields. Keep model-specific option
  names, explicit bindings and inherited selections correct.
- [ ] Verify tenant isolation and permission/credential changes, and that opening
  the editor does not fetch every provider's voice list. Confirm catalogs are not
  fetched by save, publish or call startup. No shared private cache is required.
- [ ] Inspect production-wired picker states in headless Chrome at desktop and
  mobile widths, including keyboard focus/return, long names, search/filter,
  load-more, loading, errors and a saved ID absent from page one. Check opening
  audio, defaults, TTS and STS through both editor authorization contexts.
- [ ] Run focused provider-contract, Calls/Console route and UI tests, typecheck,
  relevant static checks and documentation checks; record evidence and synchronize
  this milestone/index. Do not run live telephony or paid AI tests. An optional
  read-only catalog interoperability check needs separate explicit authorization.

## Acceptance gates

- [ ] Every installed voice-bearing capability uses the common picker in the
  actual app; Storybook-only integration is insufficient.
- [ ] Selecting a voice round-trips its exact supported identifier and configured
  binding through save/reload/publish; changed drafts publish successfully.
- [ ] Tenant/platform authorization and effective credential choice are enforced
  server-side; private voices never cross tenants or connections.
- [ ] Slow/failing catalogs and obsolete responses neither block the editor nor
  silently overwrite the current voice. Bounded pagination and cancellation work.
- [ ] Provider compatibility gates above are resolved and browser/test evidence
  is recorded without paid calls or deployment being implied by local checks.

## Specification review

Local review on 2026-11-13 is separate from implementation progress. It confirmed
that the modal and public model/default metadata already exist, while backend
voice discovery does not. It checked dependency order (contract/auth before UI,
one provider vertical slice before expansion), all editor sites, account-specific
voice access and runtime serialization. No new persistent catalog infrastructure
is required. Remaining factual questions are ElevenLabs STS compatibility, Flux
metadata coverage, and the installed Google TTS model's prebuilt set; each has an
explicit task above. No independent-agent review or live provider acceptance is
claimed.

## Implementation evidence

2026-11-13: first backend checkpoint uses bounded Req requests and the existing
credential resolver, with no persistent cache or runtime speech changes. Focused
offline tests cover the catalog (8), Calls authorization (6), and Console routes
(2). Each boundary was exercised red before implementation. UI and all-provider
acceptance are still pending.

The production editor route now supplies the HTTP catalog client. Focused route
checks select ElevenLabs voices in opening audio, defaults and an inherited
participant override, then publish a dirty draft and reload the exact ID, binding
and unrelated options. Browser acceptance remains in checkpoint C.

Checkpoint B: Cartesia account catalogs and bounded public Rime Coda/English
catalogs are implemented. Named catalogs cover Google TTS/STS (30 voices),
OpenAI GPT-Live (38), and Deepgram Flux English (36), plus finite Morse models.
Official ElevenLabs library support and its string schema support keeping account
voice IDs unchanged for Realtime Mini/Max; the design records this inference and
its offline verification limit. Focused Engine checks now total 15, including
all installed voice-bearing descriptors and pure wire serialization for every
named choice. Storybook filters match implemented capabilities. Root formatting,
compile warnings, Credo and unused-dependency checks passed.
