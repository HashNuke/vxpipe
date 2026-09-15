# Remove global readers

## Scope and decision

- Continue credential checkpoint 2 under the approved scope correction. Remove reachable global
  model/TTS/STT credential readers from the older raw-room API. No new transfer/recovery behavior.
- Preserve empty/deterministic raw rooms and inline fixture/Morse embedding. Reject the retired
  model selector and fail safe for manually constructed stale commands.
- Delete raw startup construction and the `:application` STT branch, including unused application
  options passed through attachment/activation APIs. Adapter registration, transport settings and
  limits remain host configuration; inline selections supply request options and credential names.
- Migrate existing model/speech/WebRTC contract tests to inline plans. Keep history, streaming,
  queueing, tool rejection, interruption attribution, media ingress and playout assertions.
- Use a test-only echo ModelProvider for deterministic speech responses and the existing controlled
  Agent Runtime provider for streaming tests. Live tests inject a tenant-bound credential source.

## Red/green evidence and barriers

- Initial focused raw-room run: 6 tests, 3 failures. Model selector and TTS failures were expected.
  STT setup first lacked an agent, then complete adapter options; those were fixture errors.
- Corrected isolated STT red: 1 test, 1 failure because old global credentials created media ingress.
- After reader deletion: raw-room group 6 tests, 0 failures.
- Inline fixture migration initially failed schema validation (wait_sounds belongs at the root,
  absent capabilities must be omitted, and Deepgram requires explicit encoding/sample rate).
  Corrected fixtures to the existing contract. Adapter registration still requires enabled/provider;
  retain those non-secret settings while deleting global provider_options.
- Model/speech/raw-room group: 17 tests, 0 failures (seed 235296), before adding the explicit
  stale-command assertion; that assertion is covered by the final umbrella run below.
- Independent GPT 6 Astra xhigh review found no production/credential/privacy blocker. It found
  stale single-output assumptions in the tagged live fixtures because Agent Runtime segments
  sentences. Use one long sentence for the queued-playback case and aggregate new output segments
  for the microphone transcription comparison. Bounded re-review found no remaining blockers.
- Gateway WebRTC/HTTP focused group: 18 tests, 0 failures (seed 235296).
- All five root gates passed: format, warnings-as-errors compilation, strict Credo, umbrella tests,
  and `mix deps.unlock --check-unused`.
- Final umbrella run: 1,517 tests, 0 failures, 30 excluded, seed 235296, with module preloading,
  one test-file require at a time and four concurrent cases. Per-application counts: MCP 37,
  Agent Runtime 93, Call Engine 690, Calls 81, Gateway 413, Artifacts 20, Persistence 77, Console 106.
  This includes the added stale-command regression and the existing inline Morse round trip.
- The two tagged live fixtures were corrected during the Engine portion of the root run, before
  Gateway loaded them. Their live bodies remained excluded. Final format and Credo rechecks passed.
- Live Deepgram tests remain in the excluded integration lane and have not been executed.

## Review notes

- `git diff --check` and 186 changed-document local link targets passed before final evidence edits.
- The full suite still emits existing type-comparison warnings from generated human-transfer
  test cases. The same warnings appear in the preceding source-speech root run; production
  compilation with warnings-as-errors passes. No unrelated test refactor is included.

## Checkpoint outcome

The global raw-room credential bypass is removed. Checkpoint 2 remains partial for destination
binding/save-before-write and whole-selection coverage; this commit does not complete the milestone.
The milestone still has 1 of 7 checkpoints complete, 2 partial and 4 not started.
