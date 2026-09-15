# Speech transport privacy

## Checkpoint scope

Extracted the completed speech transport change from the larger inline-selection work after
the user correctly pointed out that too many passing tasks had accumulated uncommitted.
This checkpoint is independent of the new schema and tenant activation wiring. It includes
the transport, its local wire fixtures, state redaction, documentation and direct dependencies.

## Red/green and decisions

- WebSockex authorization telemetry reproduced in both STT/TTS checks: 2 expected failures,
  seed 373684. Replaced Engine's direct use with already-locked Mint/Mint.WebSocket.
- Close during pending TTS output initially failed, seed 613074. Asynchronous acknowledgement
  preserved the 15-second deadline and allowed close to complete.
- A coalesced HTTP upgrade/provider frame initially failed, seed 820508; preserving and
  decoding upgrade data fixed it. Pending-payload inspection failed, seed 932304; the private
  Inspect projection fixed it. A timing-dependent separate-write test was replaced with the
  deterministic coalesced fixture before that fix.
- Combined provider/inline checks previously passed 58 tests, seed 147451. Those checks included
  other uncommitted work, so the exact extracted checkpoint is also verified in an isolated
  checkout against its committed parent before committing.
- The earlier independent investigation identified the WebSockex disclosure. Its follow-up
  review hit the model usage limit; do not claim an independent final transport review. Local
  source review checked upgrade deadlines, close/acknowledgement ownership and redaction.

## Verification

Verified the 13-file checkpoint in a detached checkout of parent `1bc5de8`, with its own
build/dependency trees and no inline-schema changes:

- Engine: `mix test test/integration/speech_socket_privacy_test.exs
  test/vxpipe/call_engine/provider/deepgram
  test/vxpipe/call_engine/capability/speech_to_text_redaction_test.exs --include integration`:
  **25 tests, 0 failures**, seed 781417.
- Umbrella `mix format --check-formatted`: passed.
- Umbrella `mix compile --warnings-as-errors`: passed.
- Umbrella `mix credo --strict`: passed, 892 files, no issues.
- Umbrella `mix deps.unlock --check-unused`: passed; `mix.lock` unchanged.
- The first isolated test attempt started before copying dependency files finished and exited
  with missing-dependency errors. After the copy completed, the command above passed.
- Full umbrella verification remains part of the combined cutover's completion checks; the
  last committed baseline passed 1459 tests before this extracted change.
