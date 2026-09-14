# Human handoff audio acceptance

## Scope and decisions

Close the human-web acceptance item for a real URL download, received wait/cue/conversation
ordering, and private content remaining outside model history. Reuse the native WebRTC/RTVI
handoff and recovery cases; no UI or production behavior changes are intended.

## Public URL fixture

The normal ReqFetcher rejects loopback and private addresses. A local HTTP fixture or the
Tailscale dev host would require bypassing that production rule, so neither is used here.
An initial search through public WPT and SciPy WAV fixtures found unsupported sample rates,
channel counts or sample formats. This search was a detour and did not change production limits.

[HTTPbun's documented mix endpoint](https://httpbun.com/) can return a supplied base64 body
and Content-Type. A generated, synthetic 250 Hz PCM16 mono WAV at 48 kHz needs only one
4 ms period (428 bytes with its header). A real HTTPS GET returned status 200, audio/wav,
and those exact bytes. The endpoint expects standard base64 with escaped path characters;
URL-safe base64 returned HTTP 400. No user audio or private information is sent.

The new live URL variant uses an empty isolated cache and the production ReqFetcher, including
DNS, public-address validation, TLS, size/MIME validation and decoding. It is explicitly tagged
integration and excluded from the default suite. Other configurations retain deterministic fetches.

## Acceptance changes

- Inspect cue and conversation on one decoder timeline for each native peer. Reject custom wait
  tones after the cue and cue tones after conversation, including queued packets after activation.
- Complete the destination's private briefing before simulating destination loss. Verify its tone
  reaches that peer and does not reach the caller. After recovery, inspect actual model requests
  for retained caller content and absence of the private notice, held-input marker and wait URL.
- Keep the existing recording/STT isolation and bidirectional conversation/transcript assertions.

## Verification

The focused Gateway command passed ten cases (30 excluded), including the live URL case:

```shell
cd apps/vxpipe_gateway
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --include integration --name-pattern 'human handoff gates|recovers the held caller' --seed 235296
```

This is additional acceptance evidence for existing behavior; no runtime implementation changed.
The public GET preliminary check and the actual ReqFetcher/native case both passed. The latter
also exercises the existing audio/STT/recording boundary and bidirectional support transcripts.
The human audio acceptance task is complete; remaining checkpoint work falls from 24 to 23.
The earlier intermittent recovery concern is still open despite this passing recovery run.

All five root gates pass:

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix credo --strict`
- `mix test --max-cases 4 --seed 235296`: 1,374 tests, zero failures, 16 exclusions.
- `mix deps.unlock --check-unused`

The Gateway run has 371 tests, including the 39 default native startup/transfer cases. The new
public-URL integration case accounts for one additional default exclusion; it passed explicitly
in the focused ten-case run. Retained command logs use the `vxpipe-handoff-audio-focused.log`
and `vxpipe-handoff-audio-gates-*` names. No development server restart was required.
