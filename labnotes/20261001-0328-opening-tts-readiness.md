# Opening TTS readiness

## Observed failure and decision

The provider-session checkpoint's same-seed umbrella rerun finishes with one
failure in text opening recording. Caller output preparation completes before
the opening TTS capability has received its provider acknowledgement. Synthesis
then fails with `:not_ready`, and the room closes with
`:opening_audio_unavailable`.

Wait for the opening voice's readiness resource in the existing asynchronous
opening preparation task, using the call's existing startup deadline. The voice
is installed into opening playback only after the collector confirms readiness.
This keeps room callbacks responsive and permits file opening independently of
agent/model readiness. No synthesis queue or provider contract changes are used.
The room-owned collector monitors the voice and preparation owner; deadline,
failure and owner termination retain the existing failure/cleanup paths.

## Red, repair and test adjustments

- An explicitly delayed fake TTS acknowledgement reproduces room closure before
  acknowledgement: one selected test fails, seed 252955, with `:not_ready`.
- The focused regression verifies output readiness, continued closed input
  admission and no premature TTS request, then releases the acknowledgement and
  checks the exact opening text is submitted.
- Initial post-repair test drafts tried to finish playout but mistook queued wait
  audio callbacks for the opening callback. The regression now checks only the
  readiness boundary; existing opening tests own full playout acceptance.
- The collector's ordinary 100 ms poll added delay at a boundary whose existing
  focused assertions use 100 ms. Opening preparation uses a 10 ms collector poll;
  the other collectors retain their defaults and no test deadline is extended.
- The regression explicitly shuts down the still-pending room before test-owned
  connections are cleaned up. The shared test cleanup tolerates an already-gone
  process when a failure test has confirmed room termination.
- The complete opening-audio file passes 24 tests, zero failures, seed 445906,
  in 7.8 seconds. It covers text/file playback, cache reuse, recording exclusions,
  fixed greetings, missing assets and independent readiness blockers.

## Completion gates

All five root completion checks terminate successfully. The umbrella test run
passes 3,013 reported tests with zero failures and 93 exclusions, seed 705441.
CallEngine passes 1,806 tests and Gateway passes 522. Strict Credo checks 1,176
sources and reports no issues. The existing Lean build/oracle/replay passes one
test, zero failures, seed 867759. This changes no formal transition model.

After simplifying the test observer to read struct fields directly, its focused
regression passes one test, zero failures, seed 400966. The final compile and
strict Credo checks also terminate successfully. No runtime behavior changes
follow the passing umbrella and Lean runs.
