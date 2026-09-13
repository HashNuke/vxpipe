# Transfer readiness implementation

## Scope and design review

The user authorized implementation of the complete transfer-readiness/wait-sounds milestone,
including the renamed `transfer_joining` slot. Work begins from a clean tree. Preserve the full
milestone: schema/assets, private independent playback, resource readiness, startup waiting,
coordinated agent/human handoffs, failure handling, web/phone verification and all root gates.
No runtime acceptance is claimed by the first checkpoint alone.

Read the milestone/index, prerequisite specifications, approved transfer/acceptance/privacy
contracts, current independent opening-audio contract and incremental policy contract. Reviewed
ownership: pure definition compilation selects sources; call preparation fetches/normalizes assets
before admission; live authority owns neither network preparation nor media pacing. URL values,
explicit silence and omission remain distinct. Readiness and the cue remain required with silence.

## Definition and asset checkpoint

- Five schema regressions failed on missing fields/old schema before implementation. The current
  schema is `20260914.01`; `20260913.01` remains accepted with its original closed fields and
  schema identity. Its newly prepared calls resolve omitted waits to the approved defaults.
- All 53 compiler tests pass. JSON/Elixir parity, destination defaults, per-slot/whole-object nil,
  exact URL selection, safe inspection, malformed fields and compatibility are covered.
- Five asset tests first failed because preparation was absent. Shared sources now load once per
  preparation, use the bounded existing fetch/address/cache path, and normalize mono/stereo PCM16
  to 48 kHz mono. URL cache entries have a 60-second preparation freshness window; older entries
  are fetched again, while already prepared calls retain immutable bytes. Opening assets keep
  their existing mono-only profile and cache behavior.
- The real bundled WAVs revealed malformed RIFF sizes: ChucK included the eight-byte RIFF header.
  Corrected only those four-byte size fields in the engine copies, preserving all samples and
  authoring originals. Remote WAV decoding remains strict. Generated a 250 ms, 1 kHz connection
  cue at -6 dBFS with 5 ms edge ramps. The 11 asset/opening-pipeline tests pass.
- Calls preparation now pins normalized assets/digests before creating a call/token; web and
  telephony share that factory. Embedded startup prepares an unprepared plan before creating a
  room. Prepared manifests deduplicate bytes by content digest and exclude contents from inspect.
- Admission regressions reproduced an unsafe URL being admitted and missing prepared assets.
  All 12 admission tests now pass. The memory repository returns `:error` for absent calls;
  corrected the fixture expectation after the intended asset rejection passed.
- The PostgreSQL reconstruction regression failed on missing prepared assets and now passes:
  source selection, normalized bytes, cue, and the complete plan/digest survive retrieval.
- Formatting, warnings-as-errors compilation and strict Credo pass. The final umbrella run passes 1,025 tests with zero failures and 15 existing integration exclusions.

- Full-suite verification initially exposed the opening tests' tiny 256/1,024-byte asset caches,
  which could not store the newly required default loops. Increased only those fixture caches to
  4 MiB while retaining their existing download/duration limits. All 14 opening room tests pass.
- A legacy serialized plan regression reproduced missing wait fields at runtime preparation.
  Explicit hydration at the engine preparation boundary supplies the new defaults without mutating
  original serialized history, identities, participants or schema. Already prepared manifests are
  returned unchanged. All six wait-schema tests pass.

Final first-checkpoint gates: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix test` (1,025 tests, zero failures), and
`mix deps.unlock --check-unused` all pass. No UI behavior changed in this checkpoint; rendered
browser/live-provider acceptance remains part of the following runtime work. The development
sample selects the new schema and omitted-slot defaults with `wait_sounds: %{}`.
