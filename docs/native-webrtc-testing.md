# Native WebRTC startup and transfer checks

Use the existing ExWebRTC peers in
`apps/vxpipe_gateway/test/vxpipe/gateway/http/human_transfer_webrtc_test.exs` to reproduce
handoff, readiness, audio and transcript failures. These exercise real local WebRTC connections
and the ordinary Gateway signalling handlers. Browser interaction is unnecessary for these
contracts. Keep rendered browser checks for actual UI changes and browser interoperability.

Run the complete transfer boundary from the owning application:

```shell
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs
```

For human wait configurations, cue/conversation ordering and private model-history isolation,
including a real public HTTPS WAV download:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --include integration --name-pattern 'human handoff gates|recovers the held caller'
```

The `live_url` case uses [HTTPbun's mix endpoint](https://httpbun.com/) to serve a generated
250 Hz, 48 kHz PCM16 WAV. It requires public internet access and uses the production fetcher,
public-address policy, TLS, MIME/size checks and an empty cache. It sends only a synthetic tone
in the URL. This case is excluded from the default suite; the controlled custom-URL variant
remains deterministic. Both peers receive the wait, cue and conversation in order. The recovery
case plays the private notice and checks actual subsequent model requests for retained caller
content without private notice text, blocked caller input or the configured wait URL.

The ordinary handoffs include a third planned human with its own selected recognizer. Destination
STT, that remaining recognizer and the room recording writer each become the final readiness
blocker in custom/nil configurations. All three peers decode the cue before conversational tones;
held microphones are discarded, subsequent audio reaches STT/recordings, and the remaining
participant retains its existing speech and media bindings. Additional planned humans resolve
their selected STT on attachment through the same supervised runtime path as initial callers.
The private briefing transport must stop after playback acknowledgement and before acceptance;
subsequent waiting, cues, required STT and conversation continue independently of that retired TTS.

For independent resource loss during preparation, adoption and partial release:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'human handoff gates.*loss'
```

Nine three-peer cases lose destination STT, remaining-human STT or required room recording at
each stage. The adoption cases pause the actual destination acknowledgement while output remains
held; the release cases confirm its output gate is already open before injecting loss. Required
speech loss waits for the transport to terminate. No fatal case may activate the desk or report
completion to a caller. Destination loss before adoption instead restores the original recorded
conversation: retained listeners receive cues before conversation, the caller hears the restored
assistant, human audio reaches the remaining recognizer and recordings, and authorized assistant
text reaches the other listener without taking over its local spoken-turn queue. Synthesized replies
use the requesting caller's output; the other listener's audio assertion uses the mixed human route.

For early human-transfer failure and recovery:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'recovers the held caller after (briefing_destination|briefing_voice|briefing_timeout|acceptance_timeout)'
```

These cases disconnect the private destination during briefing, fail its voice provider, or let
the configured five-second total attempt timer expire during briefing or acceptance. Each requires
one private-admission release, old-phase termination, no destination activation, the correct
bounded failure reason and recovery on the retained caller/media actors. The native caller receives
its recovery cue and spoken assistant response, then submits another turn. The existing
`destination` loss case also completes another transfer after recovery. Passing these cases does
not establish the cause of the separately recorded intermittent recovery failure.

For the local speech-provider round trip:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs --only morse
```

The peers exchange ICE/DTLS/SRTP/SCTP traffic. HTTP signalling invokes the real Plug endpoint
in process; it does not verify deployment TLS or a reverse proxy. The fixture owns room/session
setup and supervised peers, so an existing development server and external speech credentials
are unnecessary. These checks also run in the ordinary umbrella suite, except the explicitly
tagged public-URL integration variant above.

For independent model/voice preparation and failed-model recovery:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'AI handoff|agent_model loss'
```

These use the existing controlled provider to delay model initialization before withholding
TTS readiness. They verify waiting audio and held text at both stages, cue-before-greeting,
and spoken recovery through the retained source when model preparation fails. The Morse case
uses the real local speech providers; precise readiness failures use controlled providers.

For policy revisions after handoff adoption but before media release:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'after_.*adoption.*preparation'
```

Three native cases remove speech demand, make an unrelated revision, or change the permissions
of a still-required recognizer. Unaffected media actors remain installed; only the affected STT
transport is replaced, and its readiness gates completion. Both peers exchange audio after the
handoff. Exact fresh-cue drain and unchanged deadline checks also run in the owning engine suite.

For policy changes during an outstanding media-release acknowledgement:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'release_.*change preparation'
```

These two cases close the room and its media connections without transfer activation when release
can no longer be validated. They complement the successful retries before release shown above.

For cancellation and required destination STT loss during media release:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'release_(deadline|speech_loss)'
```

These pause the real destination release command, cancel the attempt or disconnect its required
recognizer, and observe terminal failed progress on the caller's RTVI channel. All room connections
close without activation, recovery or redial. The engine suite also queues a real successful recovery
result behind cancellation and verifies that cancellation wins; its release cases check failure history.

For initial caller waiting during independent model and voice startup delays:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --only initial_wait
```

Room creation returns while model construction is blocked. Ten cases cover default, URL-selected,
per-slot nil and whole-object nil waiting, with and without file/text openings. Selected STT/TTS
readiness and a local recording writer are delayed independently. Held microphone audio reaches
neither STT nor recordings; conversation reaches both after readiness. File/text notices take
priority over waiting, then waiting resumes while model setup remains blocked. The fixed greeting
follows release once, including repeated client-ready, and opening text stays out of model history.
The URL fetcher is controlled; these checks exercise selected bytes and native playout, not live
CDN retrieval. Exact PCM cursor continuity and late readiness after skipped waiting are checked
at the owning engine output boundary.

For deterministic incoming phone startup and the existing phone-transfer regressions:

```shell
mix test test/vxpipe/gateway/telephony/telnyx_call_harness_test.exs \
  test/vxpipe/gateway/telephony/twilio_call_harness_test.exs
```

The signed provider ingress, negotiated phone codecs, selected STT, normal and silent startup,
original readiness/duration clocks, failure before/after media attachment and provider hangup
submission are exercised locally. Provider adapters and playback-mark acknowledgements are
controlled; live carrier audibility remains a separate acceptance boundary.

## Protocol boundary

The caller's `chat` data channel carries RTVI 2.1 messages with `label: "rtvi-ai"`, including
`client-ready`, `send-text` and received `user-transcription` messages. The correlated `bot-ready`
reply waits for complete startup readiness and opening completion. A connected peer can receive
setup waiting before that reply. Transfer progress uses
the existing `server-message` envelope, with `data.t: "vxpipe.transfer"`, `data.v: 1`, and
`data.d` containing attempt ID, destination, phase, blocker categories and elapsed milliseconds.
Recovery and failure progress also carry an optional `reason` code: `timeout`,
`destination_disconnected`, `speech_to_text_unavailable`, `text_to_speech_unavailable`,
`media_unavailable`, `policy_changed`, `preparation_failed`, or `unavailable`. These reflect the
known engine failure category, never provider error text. Successful transfer progress omits the
field; successful source recovery retains the reason the transfer failed. Both the caller's RTVI
channel and the destination's `transfer.progress` sideband carry it. Recovery progress is sent
before private-destination cleanup; the caller still receives the outcome if the desk has gone.

The human destination's `vxpipe` channel carries the existing transfer controls. It waits for
`transfer.acceptance_ready` after the private briefing, sends `transfer.accept` with the exact
attempt ID, and awaits `transfer.active`. Media remains held through readiness and cue drain.
This is a Vxpipe acceptance channel alongside RTVI; audio travels over RTP, not in those messages.

## Transfer diagnostic observations

The existing `Vxpipe.Console.TelemetryReporter.snapshot/1` includes `transfers.phases` for
audience, preparation, release, recovery, briefing, acceptance and cue durations. Briefing ends
after acknowledged playback; acceptance ends on valid acceptance or failure. Cue durations are
per finite playback episode through final drain, including repeated cues after readiness changes.

Additional bounded aggregates under `transfers` are:

- `workers`: counts of confirmed `cancelled` phase workers and exact monitored `unexpected`
  exits, observed by the surviving supervisor or room authority.
- `playback`: sample count and peak depth/capacity by wait/cue kind and playback status. Depth is
  occupied player output slots in the current frame/drain batch, with one slot per sink. Samples
  occur on the first frame, every 50 frames and drain/terminal transitions; this is not a live
  per-listener queue view.
- `output_drops`: rejected/discarded output frame submissions by room/direct source and bounded
  reason. These measure arbiter admission and clearing, not RTP/network loss.

The corresponding new telemetry events are `[:vxpipe, :call_engine, :transfer, :worker, :stop]`,
`[:vxpipe, :call_engine, :wait_sounds, :pressure]`, and
`[:vxpipe, :gateway, :audio_output, :drop]`. Existing transfer phase events carry the additional
durations. Metadata has fixed categories; the reporter removes private fields before queueing.
These observations add no call configuration or UI component.

## Audio boundary and evidence

The Morse case selects real local Morse STT/TTS with a scripted model response. It:

- Sends paced 48 kHz Opus caller audio and receives exact transcripts from 16 kHz Morse STT.
- Decodes the assistant's synthesized Morse reply and the destination's private briefing.
- Accepts the human transfer, verifies both connection cues, and receives the support transcript
  at the original caller alongside the distinct 700 Hz conversational signal.
- Sends another caller utterance and verifies its transcript and audio at the support peer.
- Checks that the caller's existing speech ingress and native decoder survive the handoff.

Gateway converts negotiated Opus into the selected PCM speech format when needed. Readiness
prepares that same format and decoder before release. Opus speech providers retain their existing
passthrough. Decoder state belongs to the existing connection and is reused for unchanged input;
the room mixing path retains its own existing normalizer.

Use the configured Morse timing/detection settings in this fixture for Opus audio. Pristine PCM
defaults and bursting an entire utterance are unsuitable substitutes for a paced microphone.
Keep encoder/decoder history and RTP sequence continuity across utterances. Consume verified
cue tails before measuring subsequent conversation.

Exact symbol reconstruction after the human bridge's second Opus encode remains timing-sensitive.
The bridge assertions therefore combine exact STT transcripts with peer-decoded spectral evidence;
TTS reply/briefing assertions decode the actual text. These checks establish transport and provider
behavior, not physical speaker audibility or external provider availability. Existing controlled
provider tests remain useful for delaying readiness and injecting precise failures.
