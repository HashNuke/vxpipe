# TTS egress buffer overflow

Status: resolved by `f832681`

## Summary

The WebRTC audio egress originally allowed 100 queued Opus packets. Each packet
represents 20 ms of audio, so the queue could hold approximately two seconds of
audio:

```text
100 packets × 20 ms = 2,000 ms
```

This was intended to bound per-connection memory. It accidentally became an
effective response-length limit because a TTS provider can generate audio much
faster than the gateway can play it in real time.

## Failure mode

The provider delivers raw 48 kHz, mono, 16-bit PCM in bursts. The gateway turns
that stream into 1,920-byte PCM frames, encodes each frame as Opus, and sends one
RTP packet every 20 ms.

Before the fix, an incoming provider burst that exceeded the remaining
100-packet capacity caused the egress process to return `:queue_full`. The TTS
capability treated that sink failure as fatal, which terminated the capability
and caused the room connection to close. The visible symptoms were truncated
audio, no response to later input, and a server-side process failure.

The limit did not originate in WebRTC, RTP, RTVI, or the TTS provider. It was a
Vxpipe queue policy whose overflow behavior was incorrect.

## Current behavior

The default queue capacity is 500 packets:

```text
500 packets × 20 ms = 10,000 ms
```

This is a ten-second burst buffer, not a ten-second utterance limit. RTP starts
playing as soon as the first packet is ready. If the queue fills, Vxpipe retains
the unaccepted portion of the current provider frame and delays acknowledging
that write. As 20 ms pace ticks drain packets, the pending frame advances. The
blocked provider adapter therefore receives backpressure through the synchronous
sink boundary instead of an immediate failure from audio egress.

Consequently, responses longer than ten seconds remain supported. The process
itself stores no more than the configured packet reservoir plus one provider
frame at a time.

## Why the default is 500

The value provides enough elasticity for ordinary TTS responses that arrive in
a faster-than-real-time burst while keeping memory bounded per connection. It
also allows the provider to finish many ordinary responses early enough for the
gateway to know their total packet count while the remaining packets continue
through paced playout.

The exact number is an operational default, not a protocol requirement. A
smaller value would use less memory and engage backpressure more frequently. A
larger value would absorb longer bursts but retain more interruptible audio and
consume more memory per active connection. An unbounded queue would avoid
capacity pressure but would weaken overload isolation.

Future configuration should preferably express this setting as a duration,
such as `audio_egress_buffer_ms`, and derive the packet count from the negotiated
packet duration. The current `maximum_audio_packets` setting remains configurable
for deployments that need a different memory/latency tradeoff.

## Verification

The provider-backed WebRTC regression test submits a response whose first turn
produces more than 100 paced RTP packets, then submits a second text turn after
the first begins playing. It verifies that both turns complete in order, the
connection remains usable, and the first response remains pending until its
paced playback completes.
