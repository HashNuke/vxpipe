# STS transfer lifecycle hooks

Date: 2026-09-26. Starting revision: `6d6153ad`.

## Work and evidence

- The room transfer coordinator calls `SpeechToSpeech.hold/1` before
  preparation, `SpeechToSpeech.release/1` after recovery, and
  `ParticipantTransfer.teardown_source/3` after source completion. Existing
  transfer suites cover the coordinator's success and recovery paths; this
  checkpoint exercises those provider-facing hooks with room-owned STS trees.
- Added a Morse duplex case and a fake GPT-Live socket case. Each holds the
  source, releases it and verifies the same provider process accepts new input,
  then holds it again and calls transfer source teardown. Both the provider
  and capability terminate, and the room binding is cleared. The GPT-Live case
  acknowledges mute and unmute events and verifies the original socket remains
  in use after release with no replacement after teardown.
- The tests passed with the existing implementation. No runtime change was
  needed. This proves the provider-facing transfer lifecycle; the remaining
  E exit also needs the Morse scripted close/reseed cases described in the
  completion plan.

## Verification

- Focused CallEngine room authority STS file: 24 tests, zero failures with
  seed `963322`.
- From the umbrella root, `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix deps.unlock --check-unused`, and `bin/verify-lean` passed.
  `PGHOST=/var/run/postgresql mix test` passed 2,845 tests with zero failures
  and 59 tagged exclusions.
