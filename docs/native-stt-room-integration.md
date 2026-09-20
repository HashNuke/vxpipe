# Native STT room integration

## Decision

Each attached audio connection owns one temporary supervision tree below the room capability
supervisor. That tree contains a speech capability scope, the room STT policy capability, its
bounded media ingress, and every provider allocation started for the connection. The capability
remains the room policy and turn-projection boundary. It consumes acknowledged `Speech.Event`
values and projects them into the existing room signal contract, so room authority, barge-in,
attribution, readiness and transcript routing retain one state owner.

Morse and Deepgram implement the same `Speech.STTProvider` contract. Morse decodes PCM directly.
`Provider.Deepgram.Flux.Session` privately starts `FluxSocket`, translates Deepgram frames into
typed events, rejects duplicate or stale upstream sequence IDs and stops on wire failure. The
room never sees a socket, parser message or provider-specific transport callback.

The runtime has one provider shape: semantic public options plus trusted private initialization.
Deepgram credentials, endpoint and wire settings stay in its private configuration. The removed
`transport` and `transport_options` settings reject as invalid configuration. There is no bridge,
reconnect, replay or fallback provider.

Prepared sessions use the capability as their internal lease authority while policy preparation
continues to monitor the external owner and deadline. Before adoption, the channel may accept
provider readiness but discards transcript and turn events. A delayed prepared-provider event
therefore cannot acquire a later privacy interval.

## Removed structure

The direct cutover deletes the old STT provider and transport behaviours, the Deepgram bridge,
the transport connector, the global `SpeechToTextConnectionTaskSupervisor`, and the Morse JSON
transport adapter. `Capability.SpeechToText.State` now owns one semantic session instead of
parallel session/connector/transport modes. `SpeechToTextRuntime` no longer carries a transport
field. Private socket helpers remain because they own actual Deepgram wire I/O.

## Rejected alternatives

- A shared application speech supervisor couples unrelated calls and gives unrelated startup
  work a common failure and admission boundary.
- A participant-owned tree assigns connection audio lifetime to the wrong owner and complicates
  connection replacement and transfer preparation.
- A Deepgram compatibility wrapper preserves two execution models and duplicate state in the
  room. Migrating Deepgram to the same session contract is smaller once Morse is already native.
- Rebuilding media policy, ingress, turn detection or barge-in inside providers would create a
  second authority. Providers report semantic evidence; the room decides what it means.
- Automatic reconnect, request replay or provider fallback can duplicate or misattribute audio.
  A failed allocation becomes unavailable and explicit room policy decides whether to replace it.

## Implications

Loss of the speech scope closes capability, ingress and provider allocation through the
connection tree's `:one_for_all` policy. The room retires only the unavailable connection-local
workers and leaves sibling connections running. Explicit teardown terminates the exact tree.
Provider replacement stays inside the two-slot local scope and prepared results remain fenced
until adoption.

Call Specs and public provider names do not change. The closed catalog maps Deepgram STT to its
session implementation, while trusted host configuration supplies the private wire dependency.
Usage identity still comes from the descriptor and existing credential/selection binding.

## Verification evidence

The local wire test starts the native Deepgram session against a controlled WebSocket server. It
receives a `Connected` frame coalesced with the HTTP upgrade, emits readiness before ordered turn
events, and drops a duplicate sequence carrying forbidden text. Existing socket tests cover auth
privacy, rejected and stalled upgrades, bounded close and no reconnect. Capability tests cover
provider-acknowledged readiness, malformed frames, disconnect failure, duplicate sequences,
policy replacement, late old results, usage settlement and safe telemetry. Startup isolation
holds a Deepgram wire while a sibling Morse room recognizes PCM.

The direct-cutover focused evidence includes the 101 serial room/startup tests plus the policy,
capability, plan-startup, lifecycle, barge-in, readiness, Morse round-trip and local-wire lanes
recorded in the checkpoint labnotes. Cross-application configuration fixtures are migrated to
the semantic shape. The direct WebRTC microphone test initially found that ExWebRTC reports the
default Opus RTP capability as two channels; the strict mono descriptor therefore rejected the
old frame projection before the private wire. An FMTP-based repair made the local full-duplex
fixture pass, but a real libopus probe disproved its premise: the parameter is a receive
preference and the packet TOC carries the actual mono/stereo mode. The final connection boundary
keeps the negotiated decode envelope and one connection-local mono-output libopus decoder
history across mono and stereo packets. A PCM provider receives decoded mono PCM directly; an
Opus provider receives every packet from one continuous mono encoder owned by the prepared
speech input. Matching negotiated metadata does not bypass Opus normalization. Room input uses
the same decoder contract inside its Membrane chain. Empty/invalid packets are dropped, and
receive-only connections discard input before inspection.

Twenty-two deterministic Gateway boundary tests pass with real libopus packets, including exact
single-history input and output transitions, matching-metadata normalization, actual
capability-to-ingress preparation and the two connection-shutdown regressions. The real-ingress
test first failed because the capability binding omitted `channels`; preserving codec, sample
rate and channel count repaired preparation without weakening the strict provider descriptor.
Fifteen audio-pipeline and egress tests also pass, including the room-input continuity
regression. A
four-scheduler benchmark at 32 synchronized calls recorded full decode-and-encode transition
completion p99 of 5.135 and 5.514 ms in two consecutive controlled runs, with zero missed 20 ms
deadlines. Three local full PeerConnection tests pass; the extended full-duplex case reaches
`bot-ready`, ignores empty input, and delivers normalized stereo and following-mono Opus while
agent output is active. The strict provider descriptor and no-fallback decision remain
unchanged. See the [WebRTC Opus stereo decision](issues/webrtc-opus-stereo-input.md). A final
semantic load completed 38,400 turns at 32 calls with zero failures. Repeated final codec runs
kept transition operation p99 below 1.7 ms; deadline misses varied with scheduler wake lag and
also appeared in no-codec controls, so they do not prove change-caused instability. All five
root gates pass: 1,937 tests, zero failures and 41 excluded with seed 530504. The
credential-dependent live Flux/RTVI lane remains separate exit evidence.
