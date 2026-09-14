# Native WebRTC transfer checks

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

For the local speech-provider round trip:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs --only morse
```

The peers exchange ICE/DTLS/SRTP/SCTP traffic. HTTP signalling invokes the real Plug endpoint
in process; it does not verify deployment TLS or a reverse proxy. The fixture owns room/session
setup and supervised peers, so an existing development server and external speech credentials
are unnecessary. These checks also run in the ordinary umbrella suite.

For independent model/voice preparation and failed-model recovery:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'AI handoff|agent_model loss'
```

These use the existing controlled provider to delay model initialization before withholding
TTS readiness. They verify waiting audio and held text at both stages, cue-before-greeting,
and spoken recovery through the retained source when model preparation fails. The Morse case
uses the real local speech providers; precise readiness failures use controlled providers.

## Protocol boundary

The caller's `chat` data channel carries RTVI 2.1 messages with `label: "rtvi-ai"`, including
`client-ready`, `send-text` and received `user-transcription` messages. Transfer progress uses
the existing `server-message` envelope, with `data.t: "vxpipe.transfer"`, `data.v: 1`, and
`data.d` containing attempt ID, destination, phase, blocker categories and elapsed milliseconds.

The human destination's `vxpipe` channel carries the existing transfer controls. It waits for
`transfer.acceptance_ready` after the private briefing, sends `transfer.accept` with the exact
attempt ID, and awaits `transfer.active`. Media remains held through readiness and cue drain.
This is a Vxpipe acceptance channel alongside RTVI; audio travels over RTP, not in those messages.

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
