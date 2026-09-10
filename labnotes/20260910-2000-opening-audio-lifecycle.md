# Opening audio and call lifecycle

## 2026-09-10 — source schema checkpoint

- Started from `milestone/opening-audio-call-lifecycle` after the remote-MCP milestone was
  merged and pushed.
- Chose a closed tagged source object: `text` carries fixed text and `file_url` carries an
  HTTPS URL. Mixed sources, unknown keys/types, credential-bearing URLs, fragments, empty text,
  and oversized values fail during call-definition parsing.
- The source becomes typed data in the immutable resolved plan. Routine inspection exposes
  only its type so configured text and URL query data do not leak through ordinary logs.
- Released the additive call-definition shape as `20260910.02`; current fixtures and the
  development definition now select that version.
- Red evidence: the focused test first failed because `OpeningAudio` did not exist, then failed
  because the schema still reported `20260910.01`.
- Green evidence: from `apps/vxpipe_call_engine`,
  `mix test test/vxpipe/call_engine/call_definition/opening_audio_compiler_test.exs --seed 238092`
  passed with 2 tests and 0 failures.
- Broader affected-app evidence: Call Engine passed 232 tests with 1 integration exclusion;
  Calls passed 35 tests; Gateway passed 66 tests with 4 integration exclusions; Console passed
  56 tests. Root `mix compile --warnings-as-errors` passed, and strict Credo reported no issues
  across 368 source files and 3480 modules/functions.
- A root invocation of the focused test compiled the umbrella but could not create the test
  database because this shell lacks its PostgreSQL password. That is an environment barrier,
  not presented as passing umbrella evidence. Root formatting completed before that failure.
- Runtime fetch/format/cache policy, playback completion gating, greeting modes, and lifecycle
  clocks remain pending.
