# Native Deepgram STT

## Goal

Move Deepgram Flux and Morse STT behind the same semantic session contract, switch the room to
one execution path, and delete the intermediate bridge and old STT behaviours without adding a
fallback.

## Decisions

- `Provider.Deepgram.Flux.Session` owns parser-to-event translation and privately starts the
  existing bounded `FluxSocket` helper.
- `Capability.SpeechToText.State` owns only `Speech.Session`; connector/transport/mode branches
  are removed.
- Trusted `wire_module`/`wire_options` are provider-private test/network injection. Removed
  public `transport`/`transport_options` settings reject as invalid configuration.
- No reconnect, replay or provider fallback is added.
- The remaining TTS order is F then E: implement native Deepgram TTS first, then switch all
  Morse/Deepgram consumers once and delete the old TTS path. No TTS compatibility bridge.

## Red/green evidence

The first native local-wire test failed because `Provider.Deepgram.Flux.Session` did not exist.
After implementation it passed against a controlled WebSocket upgrade containing a coalesced
`Connected` frame and ordered turn frames. A duplicate provider sequence containing forbidden
text was dropped.

Focused green evidence before the WebRTC finding:

- native local-wire test: 1 test, zero failures
- plan startup and destination credentials: 13 tests, zero failures
- startup isolation: 7 tests, zero failures
- STT capability: 13 tests, zero failures
- room STT media policy: 25 tests, zero failures
- audio turn, spoken barge-in, lifecycle and readiness: 32 tests, zero failures
- Morse provider/room/telemetry bundle: 10 tests, zero failures
- serial room/startup bundle: 101 tests, zero failures
- persistence fixtures after configuration migration: 26 tests, zero failures
- `mix compile --warnings-as-errors`: green before the WebRTC diagnostic

An initial default-concurrency 101-test room bundle reported three failures. Isolated runs found
two stale fixture expectations: a default-provider assertion still named the old module, and an
opening test sent `track-opening` after readiness had bound `embedded`. Both were corrected. The
same 101 tests then passed serially. No app-instability claim is based on the unreproduced third
failure.

## Proven blocker: WebRTC Opus channel metadata

The exact Gateway test
`RTVIWebRTCTest: forwards microphone RTP to speech recognition while agent output is active`
failed twice in isolation after the cutover. `CallEngine.push_audio/2` accepted the frame into
bounded ingress, but temporary diagnostic instrumentation showed the semantic capability
returned `{:error, :unsupported_audio}` before the private wire received it. The observed frame
was Opus/48 kHz with `channels: 2`; the Deepgram descriptor is Opus/48 kHz mono.

The pre-cutover Deepgram branch explicitly accepted channel counts 1 and 2, while the semantic
path enforces the descriptor's exact channel count. That source delta plus the isolated runtime
result establishes causality. This is a real call regression: the WebRTC connection tears down
when speech delivery reports unsupported audio.

Blindly restoring `channels in [1, 2]` is unsafe. Deepgram's current official Flux material says
multichannel raw audio is rejected, and Listen v2 does not accept the old `channels` query
parameter. ExWebRTC advertises Opus with RTP `channels: 2` by default even when its negotiated
FMTP does not request stereo. This observation initially suggested deriving the incoming channel
count from FMTP, but the later real-codec proof below rejected that interpretation. Keep the
provider descriptor strict and add no fallback.

Temporary `IO.inspect` diagnostics were removed after capturing the result. The milestone goal
was paused as requested before implementing the repair.

## Rejected FMTP repair

After the user resumed and approved the bounded repair, focused tests first failed in four
places: default Opus frames and negotiated input tracks still exposed two channels, and explicit
FMTP stereo remained accepted at both boundaries. The candidate added
`Gateway.WebRTC.OpusInput`, projected absent/false FMTP stereo as mono, and rejected explicit
FMTP stereo.

Green evidence after implementation:

- audio-frame and negotiated-audio projection: 7 tests, zero failures
- audio-frame, negotiated-audio, incoming-audio and full RTVI WebRTC bundle: 11 tests, zero
  failures
- exact previously failing full-duplex WebRTC location: 1 test, zero failures

The full-duplex fixture sent four arbitrary bytes through a real local PeerConnection and
observed them at the STT wire while TTS output was active. It proved routing but did not prove
that the channel label matched the encoded payload.

The Astra review then checked the SDP semantics and ran a bounded real-libopus probe. A stereo
packet with TOC byte `252` and default FMTP retained its stereo payload while the candidate
reported one channel. A mono packet was rejected when the remote FMTP requested stereo. RFC 7587
defines that parameter as the decoder's receive preference; RFC 6716 defines the TOC `s` bit as
the packet channel mode. The candidate is therefore rejected and uncommitted. The next repair
must accept the Opus RTP mapping at readiness, classify every payload from its TOC, forward mono
as semantic mono and reject stereo before raw passthrough.

An isolated dependency investigation found `rusty_opus` 0.4.0, but it is not suitable for this
checkpoint: it requires Elixir 1.20, pins Rustler 0.36.2 while this umbrella uses Elixir 1.19 and
Rustler 0.37, and its mono decoder rejected the real stereo packet. The existing
`membrane_opus_plugin` was selected as the decode/encode boundary; simple TOC admission needed
no new NIF.

## Superseded packet-TOC repair

The intermediate repair kept SDP readiness separate from payload classification. The Gateway
accepts the standard Opus/48 kHz RTP mapping, reads the channel-mode bit from each packet's TOC,
projects mono packets as semantic `channels: 1`, and fails actual stereo or an empty packet before
raw delivery to STT. It does not decode, transcode or add another native dependency.

The focused Gateway lane passes 12 tests with real packets generated by
`Membrane.Opus.Encoder.Native`: mono passes even when FMTP requests stereo, stereo fails even
without that FMTP, and the full-duplex WebRTC test delivers a real mono packet to STT while TTS
output is active. The previously failing exact WebRTC behavior is green.

The stale media-ingress fixture was migrated from `{Flux, config}` plus the removed transport
option to `Flux.Session` plus provider-private wire injection. Its 10 tests pass. The room-policy
lane passes 25 tests; its prepared-provider failure test now waits on the public readiness
collector rather than using a capability mailbox barrier that could run before the failure
crossed the OTP monitor chain.

A Call Engine run with `--max-cases 4` completed 822 tests with eight 100 ms receive-timeout
failures: two archive, one TTS, one recording and four ingress fixture-start messages. The same
10 ingress tests pass serially, and no speech lifecycle or content assertion failed. This is
recorded as host/scheduler pressure, not product-instability evidence; lower-concurrency changed
suites and final bounded room load/root gates remain the checkpoint evidence.

## Removed code in the candidate

The candidate deletes the old STT provider/transport behaviours, the Deepgram legacy bridge,
transport connector, global STT connection task supervisor, Morse STT JSON transport, and the
obsolete scoped-speech compatibility experiment. Final line counts and root gates remain
deferred until the checkpoint diff is stable.

## Stereo implementation and final review repair

The final Astra review proved two P2 regressions against separately compiled `HEAD` callbacks.
The mono-only candidate returned `:stop` for an empty Opus RTP payload where `HEAD` returned
`:noreply`, and it inspected then stopped on stereo RTP from a receive-only monitor where `HEAD`
discarded the input. Both probes used two schedulers without application or network startup.

The user resumed the milestone and chose to implement stereo now using the installed Membrane
codec dependency. Red tests first reported 8 failures across 15 focused cases: stereo was still
rejected, input readiness projected one channel, receive-only stereo was unavailable, and the
new speech normalizer did not exist. A later callback red test proved nonempty malformed Opus
still returned `{:stop, :shutdown, state}` after speech validation.

The first stereo candidate kept one libopus decoder resource for each packet mode inside the
connection process. Final review disproved that design with a continuous mono/stereo/mono
sequence: the first mono segment matched a single decoder, then the split histories diverged at
the first stereo packet and remained divergent after returning to mono. A focused room-pipeline
test independently reproduced the same project-owned failure before the repair.

The repaired boundary keeps the negotiated two-channel WebRTC decode envelope and one
connection-local mono-output libopus decoder history. The installed Membrane wrapper rejects a
packet whose TOC channel count differs from its configured output and recreates state on mode
changes, so a small Gateway Unifex adapter calls the same precompiled libopus dependency without
that wrapper restriction. Libopus emits mono PCM for both packet modes. `SpeechInput` consumes
every packet through the decoder and, when the provider requests mono Opus, encodes every packet
through one continuous mono encoder. The room Membrane chain uses the same decoder contract
and removes its separate channel-mixer stage. Empty and invalid input is dropped. Receive-only
input is discarded before packet inspection. No shared process, fallback or replay path was
added.

A later output-history review disproved conditional mono passthrough. Forwarding raw mono
packets around newly encoded stereo packets spliced two encoder histories; a continuous
downstream decoder differed on the first following mono packet by RMS 4,567.8 with maximum
sample error 14,174. The same review proved that the generic exact-format shortcut forwarded a
real stereo packet when negotiated metadata already said mono. The milestone paused with both
reproductions. After the user resumed it, two focused tests failed for exactly those reasons
(7 tests, 2 failures). Moving generic identity handling after Opus and encoding every Opus-target
packet through the allocation-owned encoder made all seven green. The output sequence now
matches a separate continuous reference encoder packet for packet.

Focused evidence after the repair:

- audio frame, negotiated input, incoming audio, speech normalization and connection callback:
  21 tests, zero failures;
- WebRTC audio pipeline and audio egress: 15 tests, zero failures;
- speech and room mono/stereo/mono regressions compare exact PCM against separate single-history
  decoders; mono Opus output and malformed input use real `Membrane.Opus.Encoder.Native` packets;
- the extended full PeerConnection test now sends empty, stereo and following-mono RTP, but its
  latest attempts stopped before audio because local ICE/data readiness did not deliver
  `bot-ready` within the existing timeout. This is recorded as an unverified lane, not a pass.

The committed `bench/opus_input_latency.exs` was run after the output repair with
`ERL_FLAGS='+S 4:4'` on the eight-core, 16 GiB host. Each final paced lane used 32 synchronized
call-equivalent workers and 100 measured 20 ms packets. Two consecutive full decode-and-encode
transition runs completed at 5.135 and 5.514 ms p99 with operation p99 of 0.868 and 1.125 ms.
Both missed zero deadlines. Average scheduler use was 12.74% and 15.00%, with maxima of 15.78%
and 16.55% across the four enabled schedulers. Their no-codec controls completed at 2.193 and
2.206 ms p99. The unpaced transition lanes sustained 9,861.9 and 9,880.1 packets/s.

The first post-repair paced transition run recorded five deadlines above 20 ms, all in scheduler
wakeup lag while maximum codec operation stayed below 2.7 ms. Two immediate identical reruns
recorded zero missed deadlines in baseline, steady stereo and transition lanes. The anomaly was
therefore not accepted as a change-caused codec failure.
These figures prove local codec headroom for the bounded workload; they do not establish hosted
recognition quality or production call capacity.

## Real ingress descriptor repair

The final architecture review started a real supervised Morse STT capability and a real media
ingress, then called `SpeechInput.prepare/3` with the capability's public input binding. That
failed with `{:error, :unsupported_audio}` even though isolated codec tests passed. The binding
used `Map.take/2` with only codec and sample rate, while `SpeechInput.configure/2` requires a
channel count. A focused boundary test reproduced the failure first: 8 tests, 1 failure. Adding
`channels` to the binding's retained media fields made the same lane pass: 8 tests, zero
failures.

The full-duplex local PeerConnection case then reached `bot-ready`, discarded empty RTP and
delivered normalized stereo and following-mono Opus while agent output was active. Its previous
assertion expected raw mono packet identity, which is no longer a valid contract because every
Opus-target packet advances the one continuous encoder history. The corrected assertion checks
the delivered packet's mono mode. The full local PeerConnection file passes 3 tests with zero
failures.

Post-repair focused evidence:

- serial room, startup and policy bundle: 165 tests, zero failures;
- local wire, capability, credential, ingress and Morse bundle: 54 tests, zero failures;
- actual capability-to-ingress preparation: 8 tests, zero failures;
- local full PeerConnection path: 3 tests, zero failures;
- semantic load at 32 calls: 38,400 turns, zero failures, text p99 at most 6.315 ms and turn-end
  p99 at most 3.849 ms across the ordinary and held-sibling lanes.

Three final four-scheduler codec runs repeated 32 synchronized calls with 100 paced packets per
call. Transition operation p99 stayed between 0.791 and 1.633 ms. Scheduler wake lag varied:
normalized transition missed 0, 0 and 8 of the 20 ms deadlines, while no-codec controls missed
32, 59 and 0. Steady stereo missed 29, 35 and 0. Because excess latency also occurred in the
controls and codec operation remained below 1.7 ms p99, these runs do not prove instability
caused by normalization. The two earlier identical controlled runs with zero misses remain part
of the evidence; none of these local loads establish production capacity.

`mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` and
`mix deps.unlock --check-unused` passed after this repair. The first four-scheduler umbrella
test had two failures among 1,937 tests: a policy case observed an unexpected provider-start
message, and a five-participant WebRTC handoff missed one ordered audio phase. Both exact cases
passed alone with the same seed (1/0 each), so the first run does not establish a change-caused
failure. A second bounded umbrella run passed 1,937 tests with zero failures and 41 exclusions
using seed 530504. The required final GPT-6 Astra xhigh review found no remaining P0, P1 or P2
issues. Linux/release portability was outside that review and remains an explicit limit.

## Hosted acceptance follow-up

On 2026-09-20 the tagged full WebRTC/RTVI lane ran with the configured Deepgram credential and a
temporary generated 48 kHz mono Ogg Opus fixture. The final one-utterance fixture included
leading and trailing silence, produced a nonempty `flux-general-multi` transcript through the
`/v2/listen` endpoint, completed the agent response and returned nonempty output audio: one test,
zero failures (seed 530504).

Two earlier fixture shapes were rejected as acceptance evidence. The first had no post-speech
silence and timed out before turn completion. The second contained two sentences, which the
provider correctly split into two turns; the room completed, but the old test's single-final
assertion compared both echoes with only the last transcript. The passing single-utterance run
shows these were fixture/test-shape problems rather than migration-caused call instability.
