# RTVI TTS turn order

## Objective

Correct the first audible RTVI slice after a typed turn produced an empty,
temporary assistant row and the played bot audio was transcribed into recursive
user and bot turns.

## Observed behavior

- One typed `hello how are you?` appeared correctly as a user message.
- A second user message containing `echo` appeared without user input.
- An assistant typing row appeared and then disappeared.
- Playback contained the requested echo plus additional echoed fragments.

## Investigation

The gateway advertised RTVI `2.1.0` but encoded a spoken `bot-output` with only
`will_be_spoken: true`. The installed `@pipecat-ai/client-react` 2.x reducer
adds spoken output text only when the initial segment has
`spoken_status: new`; `in-progress` and `completed` events advance that same
segment's spoken cursor. With no status, the reducer created an assistant
message shell but added no text, which accounts for the ellipsis followed by
the disappearing row.

The WebRTC connection also forwarded microphone RTP into STT throughout agent
playback. Speaker output containing `Echo: ...` could therefore be recognized
as a fresh participant turn, which accounts for the unrequested user `echo`
message and repeated TTS.

Pipecat's current client documentation describes `BotOutput` as the bot text
stream, bot speaking events as audio-delivery boundaries, and
`UserMuteStarted`/`UserMuteStopped` as the standard signal that the server is
temporarily ignoring client audio. The installed client types additionally
define the RTVI 2.x `new`, `in-progress`, and `completed` spoken-output states.

## Decision

- Keep `TextOutput` protocol-neutral in the call engine.
- Make the RTVI gateway announce spoken text with `spoken_status: new`.
- Retain that segment by correlation ID for the connection's output lifetime.
- Project first paced RTP as `bot-started-speaking` followed by an
  `in-progress` cursor with none of the text accumulated yet.
- Project paced completion as a `completed` cursor with the full text
  accumulated, followed by `bot-stopped-speaking`.
- Treat this slice as half-duplex: ignore inbound microphone RTP while one or
  more spoken outputs are pending and expose the boundary with standard
  `user-mute-started` and `user-mute-stopped` messages.
- Keep the input gate closed across queued outputs. Barge-in is not implied by
  this checkpoint and needs an explicit later policy.

The gateway owns this state because it combines an external protocol's output
projection with a transport-specific input policy. The room authority continues
to describe domain turns and actual output lifecycle without knowing RTVI or
WebRTC details.

## Red-green evidence

The first focused run had five expected failures: the initial spoken output had
no `spoken_status`, the progress and mute encoders did not exist, and the turn
state module did not exist. After implementing the codec lifecycle, stateful
projection, and connection input gate, the focused codec, turn-state, and
WebRTC endpoint run passed 15 tests with no failures.

## Verification

- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed.
- `mix test` passed: 32 call-engine tests and 29 gateway tests, with the tagged
  integration lanes excluded by default.
- `mix deps.unlock --check-unused` passed.
- The live TTS integration was not run from this shell because it did not inherit
  `DEEPGRAM_API_KEY`; no secret value was read or logged.
- A browser retest with live Deepgram STT and TTS remains the final behavioral
  confirmation because the defect involved acoustic feedback at the user's
  output and microphone devices.
