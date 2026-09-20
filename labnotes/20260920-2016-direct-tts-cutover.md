# Direct TTS cutover

## Objective

Complete checkpoint E of `docs/milestones/simpler-speech-integrations.md`: move conversation,
opening and private-transfer speech for Morse and Deepgram onto the owned semantic TTS session,
then delete the old public provider/transport path and global audio-output task supervisor.

## Decisions

- The capability owns policy, queueing, playback projection and usage. Its supervised session owns
  provider lifecycle and semantic request state. One capability-local `Output` worker performs
  blocking sink calls without blocking the capability or adding a shared executor.
- `Output` uses `:gen.send_request/4`. Each pending sink operation retains its exact request ID
  until `:gen.check_response/2` matches its reply or terminal cleanup runs. This applies to push,
  finish and interruption and prevents a late reply from affecting a replacement request.
- Audio remains one-envelope/one-credit. The real Deepgram socket uses active-once delivery and
  does not re-arm provider input until the exact output credit returns. Test wires must likewise
  await `:test_tts_audio_result` before sending another frame.
- Provider completion does not mean local playback completion. The capability finishes the sink,
  waits for confirmed playout, settles cumulative played time into the semantic session, then emits
  the room playback terminal.
- Private transfer preparation waits for provider readiness inside its existing supervised phase
  task and deadline. The room GenServer stays responsive. Readiness failure closes the private TTS
  tree and outbound leg through existing lifecycle operations.
- There is no compatibility bridge, fallback provider path, public transport selection or global
  TTS work supervisor.

## Red tests and findings

- A private phone-transfer regression showed preparation and briefing could proceed after only the
  TTS tree had started, before the hosted provider emitted `Connected`. The deterministic test held
  readiness for 250 ms and initially observed preparation complete early. The readiness collector
  repair made the test and the phone/web/carrier transfer suites green.
- The full root run exposed two tests that advanced on the sink observer message before the sink
  reply had propagated as semantic audio credit. The semantic completion test returned
  `{:error, :output_pending}`; three opening-audio cases rejected their second fixture frame. These
  were fixture synchronization defects, because the production socket already stops frame delivery
  until exact credit. The tests now wait for their project-owned credit messages.
- Source restoration previously expected a blocked provider to start after the room tree had
  closed. The corrected assertion monitors the blocked wire and verifies supervised termination.
- Deepgram completion arriving behind its last audio frame is retained as `pending_terminal` and
  published only after that frame receives output credit. Cancellation during this interval releases
  the exact wire credit and produces one correlated cancellation terminal.

## Implementation outcome

- `Capability.TextToSpeech` now speaks, fences, cancels and settles output through
  `Speech.Session`; it no longer calls the old provider transport contract.
- Conversation, opening audio, private briefing, transfer preparation and source restoration use
  one semantic startup path for both Morse and Deepgram.
- The old TTS behaviours, signal/transport modules, Morse JSON adapter and global audio-output task
  supervisor are deleted. Trusted configuration uses provider sessions; Deepgram's socket remains a
  provider-private wire implementation.
- Usage snapshots are captured before acknowledgement/validation can close an allocation. Accepted
  input, generated audio, failure, interruption and cumulative confirmed playback remain correlated.

## Verification

- Focused semantic capability: 6 tests, zero failures, seed 530504.
- Persistence opening audio: 4 tests, zero failures, seed 530504.
- Call Engine root lane: 827 tests, zero failures, 14 excluded.
- Full umbrella root gate: 1,942 tests, zero failures, 42 excluded, seed 530504, with
  `ERL_FLAGS='+S 4:4'`.
- `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` and
  `mix deps.unlock --check-unused` pass from the umbrella root.
- Final bounded handoff load used four schedulers and passed 36 trials: 3 repeats across 1, 8 and
  32 scopes, direct/adopted startup and 0/2 ms sink delay. It completed 3,936 exact TTS turns,
  3,936 concurrent STT turns and 492 forced Channel failures with successful TTS replacement.
  Peak per-trial p99 was 2.665 ms to first audio and 85.237 ms through final sink acceptance;
  the latter includes the deliberate 2 ms delay for every 20 ms PCM chunk. Maximum measured memory
  growth across a trial was 398,872 bytes and the peak post-trial process count was 239.

The load is local Morse smoke/fault evidence. It does not measure physical playback, hosted network
latency or production capacity. Hosted interoperability evidence remains checkpoint F's separate
lane; final all-consumer and manual acceptance remain checkpoint H.
