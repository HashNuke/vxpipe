# TTS queue and progress

## Objective

Fix long Flux TTS output truncation and room failure, keep a rapidly submitted
second text turn ordered behind active playback, and make RTVI 2.x spoken text
advance during audio rather than remain visually unspoken until completion.

## Reported behavior

- A short typed turn produced the correct single text and audio response after
  the prior RTVI lifecycle fix.
- A longer response stopped after an early phrase while its full text remained
  visible.
- Sending another text during that playback coincided with audio stopping, no
  later reply, and a server crash.
- The Voice UI Kit kept all assistant text in its unspoken visual style during
  playback instead of advancing the spoken portion.

## Crash evidence and cause

The running `bin/dev` pane recorded the TTS capability terminating with
`:audio_output_failed` while streaming the longer response. Its request was
still in `:streaming`; no second request was pending in that crashed instance.
Inspection traced the sink error to `AudioEgress`: its fixed 100-packet queue
represented only two seconds of 20 ms audio, and a faster-than-realtime provider
burst returned `:queue_full`. The capability treats sink refusal as fatal, so
the room connection shut down and all subsequent work disappeared. A partial
final PCM frame could hit the same failure at `SpeechMetadata` if the queue was
full.

The second text did not invoke interruption or barge-in. The engine produced its
text immediately and queued only its TTS request. Exposing that second
`bot-output` before the first output completed would also overlap assistant
segments in the RTVI client, whose progress messages identify segments but whose
conversation reducer advances the active assistant message.

The previous checkpoint emitted only an empty `in-progress` cursor at first RTP
and a full `completed` cursor at the end. It did not produce intermediate
progress, which explains the consistently unspoken styling during playback.

## Provider findings

Deepgram documents a Flux TTS turn as `SpeechStarted`, binary audio, then
`SpeechMetadata`; metadata means all audio for the turn has been sent and
includes `audio_duration_ms`. The normal server messages do not include word
timestamps. Flux supports a separate `Interrupt` command with a cumulative
`playback_offset`; `SpeechInterrupted` can then return `text_spoken` and
`text_remaining`. That is the provider primitive for a future barge-in slice,
not a continuous word-alignment feed.

References:

- <https://developers.deepgram.com/docs/flux-tts/server-messages>
- <https://developers.deepgram.com/docs/flux-tts/client-messages>

## Decisions

- Keep the Opus packet queue bounded, raise its default from 100 to 500 packets
  (ten seconds), and backpressure provider frames when it fills.
- Retain at most one blocked provider frame. The Flux socket waits for the sink
  acknowledgement, so further network input is naturally backpressured rather
  than accumulated in capability mailboxes.
- Make final incomplete-frame padding wait for capacity too.
- Keep the cross-process waits bounded at 15 seconds, enough to drain the
  provider's maximum accepted binary frame at 48 kHz linear16.
- Track scheduled packets and report protocol-neutral `AgentSpeechProgressed`
  events every five packets (100 ms) once the total packet count is known.
- Convert elapsed/total audio to an RTVI `spoken_progress` prefix at whole-word
  boundaries. This is explicitly a best-effort estimate because Flux does not
  provide word timestamps. A later provider that supplies alignment can enrich
  the internal event without changing RTVI clients.
- Serialize spoken `bot-output` announcements at the RTVI connection. Text for a
  later queued response is withheld until the active spoken response completes.
- Preserve the current half-duplex contract: typed input during playback queues
  another response. It does not stop local RTP, send Flux `Interrupt`, reconcile
  `text_spoken`, or resume STT, so it is not barge-in.

## Red-green evidence

- The new long provider-burst test initially received `{:error, :queue_full}`
  instead of remaining blocked until three packets drained.
- The final-padding test initially received `{:error, :queue_full}` while the
  one-packet queue was occupied.
- Progress tests initially had no output-sink progress callback, no
  protocol-neutral progress event, and no intermediate RTVI spoken prefix.
- The queued-output test initially exposed the second `TextOutput` immediately
  instead of withholding it until the first completion.

## Verification

- Focused call-engine capability/room and gateway egress/RTVI tests pass.
- The Deepgram-backed WebRTC integration test now reproduces the reported
  sequence: it submits the original long text, waits for
  `bot-started-speaking`, and submits a second text turn while playout is
  active. Both assistant outputs reach `completed` and
  `bot-stopped-speaking` in order without losing the connection.
- The first live response alone produced more than 100 paced RTP packets,
  crossing the former two-second failure boundary, and emitted a non-empty
  `spoken_progress.accumulated_text` update before completion.
- The first version of that live assertion stopped collecting at the second
  `bot-stopped-speaking` and consequently missed the immediately following
  `user-mute-stopped`. Collection now ends on `user-mute-stopped`, the actual
  boundary at which this half-duplex slice reopens input.
- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed.
- `mix test` passed: 32 call-engine tests and 31 gateway tests, with the tagged
  integration lanes excluded by default.
- `mix deps.unlock --check-unused` passed.
- The running `bin/dev` watcher rebuilt and restarted the backend successfully.
- Live browser verification remains necessary for provider burst behavior and
  the user-visible timing of best-effort highlighting.
