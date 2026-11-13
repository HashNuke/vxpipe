# Implement voice picker

## Scope and branch

Merged committed QA into main at `1b51f116` and pushed main. Uncommitted QA
changes were left intact. Implement the provider voice picker milestone here,
using the reviewed component and existing effective credential resolver.

## Backend checkpoint

- Added authoring-only catalog describe/list/get with finite model reuse, bounded
  HTTP responses/timeouts and strict queries. No call startup dependency.
- ElevenLabs TTS uses authenticated v2 search and direct v1 ID lookup. Official
  docs describe `high_quality_base_model_ids` as recommendations, so these do not
  exclude voices; professional fine-tuning readiness is checked for the model.
- Calls enforces tenant read permission and existing platform binding rules on
  every request. Console routes use the same permission, JSON-only responses and
  no-store. The first endpoint run exposed the required route-permission map
  addition; adding routes alone correctly remained forbidden.
- Red/green: Engine 8, Calls 6, Console endpoints 2 focused tests. Synthetic
  fixtures only; no provider account requests, paid synthesis or telephony.

## Remaining

Production UI/client scope, remaining provider catalogs, browser acceptance and
final milestone gates. No deployment is claimed. Environment files were not read.

## Production editor checkpoint

- Supplied the tenant-scoped HTTP client at the production editor route and removed
  manual voice inputs. The existing picker is reused for `voice` and `speaker`.
- Included credential names in requests and lookup/dialog identity; stale requests
  are cancelled. Failed selected-ID lookups have a retry distinct from an absent
  saved voice. Opening a catalog never changes the source.
- Shared the existing connection-name selection rule for new provider selections
  and model-type switches. Explicit/inherited bindings and unrelated options stay
  intact when choosing voices.
- Focused checks: 34 voice/binding/human-inspector tests, 15 route tests (including
  opening/default/participant dirty Publish and reload), 56 adjacent editor/seed
  checks. Typecheck and changed-file ESLint passed after moving the preview's
  mutable mock transport outside React render.
- Added a preview using the real editor route and production HTTP client with
  synthetic fetch responses. Chrome inspection at 1440x1000 and 390x844 covered
  selected ID absent from page one, paging/long names, loading, errors/retry,
  empty results and Escape focus return. Mobile had no horizontal overflow.
  API authorization is covered separately by Calls/Console tests; this preview
  does not claim live-provider or hosted acceptance. A text-selector wait timed
  out despite the empty state rendering correctly; DOM inspection confirmed it.
- Preview used a temporary environment-free mirror. No environment file, live
  provider account, audio generation, or telephony was accessed.

## Provider coverage checkpoint

- Cartesia uses existing version/header rules, authenticated cursor paging and
  direct ID lookup. Rime uses bounded public metadata filtered to Coda/English;
  configured credentials are authorized but never forwarded to the public host.
- Google/OpenAI/Flux named lists reuse installed model contracts. Public Deepgram
  metadata had no Flux entries, so the documented English list is bundled.
- Official ElevenLabs Realtime library support plus the string voice schema
  supports exact account IDs; no name-to-slug mapping. Evidence and the lack of
  authenticated upstream verification are explicit in the design.
- Added seven provider boundary tests; total Engine catalog checks: 15 passing.
  Initial failures established missing provider scopes, malformed public rows and
  optional private names. Malformed data now errors; missing names preserve IDs.
  Updated the older malformed-name fixture to test a wrong type, because absence
  is documented as valid. All installed voice-bearing models resolve a catalog;
  all named choices pass public parsers and pure runtime wire serialization.
- Updated illustrative provider stories to the implemented filters and added
  Google/ElevenLabs STS examples. Typecheck and focused lint passed. Root format,
  warnings-as-errors compile, strict Credo and unused dependencies passed.
