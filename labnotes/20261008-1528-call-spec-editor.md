# Call spec editor implementation

## Scope and setup

Implement the complete V → P → L → K → S → U → C → W → Z milestone. User authorizes
frequent coherent commits and GPT Luna pushnotify updates through zsh. No live tests
or live-provider environment access. Preserve the unrelated wrangler-cache labnote.
`bin/setup` completed dependencies, frontend assets, and development/test migrations.

## Design review

Reviewed the milestone, earlier editor review, tenant authoring and operator admin
prerequisites, direction contract, routing/styling documents and current Calls/Gateway
boundaries. Calls owns error projection; no transport reaches Persistence directly.
Exhausted revision retries need the same conflict response as a direct collision.
Private-material preflight needs a path, not only an atom. Old stored compiler errors
need a safe fallback. These are contract clarifications, not scope additions.
Later checkpoints retain the full source-model, Callpipe reuse, catalog, Storybook,
production integration and acceptance scope. UI review must use a concrete rendered
Storybook before production integration. No review of an unbuilt UI is claimed.

## Checkpoint V

- Red: Gateway focused suite (seed 738953) had four failures for missing field paths,
  opaque publish errors and conflicts incorrectly returning 503. Calls focused test
  failed because private material returned only an atom (seed 305742).
- Implemented a shared Calls error projection, fail-fast compiler projection,
  specific conflict/route/private-material statuses and private-field discovery.
  Validator/compiler reason strings were inspected: they are static descriptions
  or contain only project-defined numeric bounds, never submitted values.
- Green: Gateway's ten focused tests pass (seed 96941), including seven representative
  invalid sources on create/update, private prompt/URL/number non-disclosure, publish
  and saved compiler errors. Calls verification and root gates follow.
- Test setup corrections before the meaningful red run: CallSpec.new requires
  explicit identity/revision options; CallSpecRevision requires published_at.
  The environment provides python3, not python.

## Model abstraction clarification

Inspection found a tension between finite model listings, free-text Flux voices,
and preserving previously accepted configurations. The user selected public
pseudo-model IDs with adapter-owned concrete-ID construction. Deepgram.Speech
already accepts `flux` plus `options.voice`; use it as the public listing, with
recommended voice `hannah`, while preserving old concrete model IDs. This resolves
the specification ambiguity without changing the JSON schema or adding a second
frontend-only mapping. Future provider-specific combined IDs belong behind adapters.

### Checkpoint V exit evidence

Calls' ten focused tests pass (seed 778450). Root formatting, warnings-as-errors
compilation, strict Credo and unused dependencies pass. Full root `mix test` passes
3,326 tests with zero failures and 120 exclusions (seed 947553); Gateway's 589 tests
include existing outgoing and authoring coverage. The suite took about twelve
minutes, mostly local Call Engine and Gateway media/transport exercises. The
existing test-only archive_options default-argument warning is outside this change;
production warnings-as-errors compilation is clean. Documentation file links and
`git diff --check` pass. No frontend or state machine changed in V.

P's new, uncommitted model-contract test was run separately after the root run had
finished its Call Engine phase. Its 17 failures establish the missing model callback
and direct Flux public-selection behavior; this future-checkpoint red test is not
part of V's verified/committed tree. No P implementation is included in V.

## Checkpoint P implementation and verification

- Registry-driven red contract: 17 failures because models/0 was absent and direct
  Flux configuration did not accept the public model plus voice. The implementation
  now passes all 17 checks (seed 282748 before adding the guide fixture check).
- Every production STT/TTS/STS adapter and both Morse namespaces declares models.
  Pure configuration modules own declarations; sessions delegate. Model acceptance
  uses those declarations. Legacy fallback configuration stays unchanged.
- Flux lists one public `flux` model with recommended `hannah` voice, and builds
  concrete wire IDs internally. Old combined IDs remain supported. Free-text voice
  parameters also preserve Rime's `speaker` option. Defaults and rejected alternatives
  are recorded in docs/speech-model-catalog.md.
- Added the executable guide provider to the contract test: confirmed a red failure
  (seed 9180), then taught its configuration to accept/validate its declared model
  and synchronized the guide. Test-only probe adapters declare the required callback.
- Temporarily removed Cartesia STT's models/0 locally: `mix compile
  --warnings-as-errors` failed on the missing required callback. Restored the exact
  source and warnings-as-errors compilation passed. No broken callback is retained.
- Broader owning-child run: 670 provider, speech and inline-activation tests pass,
  zero failures, 22 excluded (seed 821225). Formatting, strict Credo and unused
  dependency gates pass. Full root default suite is running; P is not complete yet.
- One probe previously had no @impl annotations; adding only one triggered warnings
  for its other callbacks. Kept that probe's existing annotation convention instead
  of expanding unrelated test-fixture changes.

### Checkpoint P exit evidence

All five root gates pass. The default umbrella suite passes 3,343 tests, zero
failures, 120 excluded (seed 468087), including existing room and adapter tests.
No live tests ran. L implementation was applied after the root run had completed
its Agent Runtime phase; it is excluded from this checkpoint and receives a
separate full suite.
