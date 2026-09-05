# No-timestamp highlighting

## Objective

Stop projecting estimated word-level spoken progress when a text-to-speech
provider supplies audio without word-alignment timestamps.

## Findings

The gateway converted internal scheduled-audio progress into an RTVI text
prefix by applying the elapsed/total audio ratio to the output's grapheme count
and rounding backward to whitespace. Pronunciation duration is not proportional
to grapheme position, so the resulting cursor could visibly lag or lead the
audio. The calculation also could not observe the browser's actual output
device.

The internal `AgentSpeechProgressed` event remains useful as transport-neutral
playout telemetry. The inaccurate behavior was specifically its projection as
word progress at the RTVI boundary.

## Decision

For output without provider alignment, announce the spoken segment as `new`,
mark it `in-progress` with an empty accumulated prefix when playback begins, and
leave the entire text pending until paced playback completes. Completion moves
the entire text into the accumulated field. Do not derive intermediate word
positions from audio duration.

Keep internal scheduled-audio progress events so another protocol or future
operational telemetry can consume them. A future timestamp-capable provider
should use a distinct alignment-bearing event before the gateway offers
progressive word highlighting.

## Red-green evidence

The focused gateway state test was changed first to require that an
`AgentSpeechProgressed` event produce no RTVI action. It failed because the
state projector still returned a ratio-bearing `spoken_progress` action. The
projector now ignores that event for RTVI while retaining start and completion
actions.

## Verification

- The focused gateway RTVI state and codec tests pass: 15 tests, 0 failures.
- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed.
- `mix test` passed: 41 call-engine tests and 32 gateway tests, with the tagged
  integration lanes excluded by default.
- `mix deps.unlock --check-unused` passed.
- The HTTPS samples endpoint and gateway health route both returned HTTP 200.
  Headless Chromium rendered the room-creation page. The provider-backed audio
  transition remains a live/manual check because external-service integration
  tests were not run.
