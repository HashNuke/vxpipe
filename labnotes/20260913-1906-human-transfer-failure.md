# Human transfer failure

## Reproduction

- The caller requested human support and the destination claimed its admission within
  the total attempt deadline. A timed-out claimed admission cannot be issued again
  for that same participant; the sample's generic error conceals that limitation.
  Opening another transfer tab alone does not consume admission; connecting it does.
- A separate development VM and two Chrome tabs reproduced private briefing and
  acceptance followed by room shutdown. The user's running server was left alone.
- Payload-free return tracing identified `media_policy_enforcement_failed` during
  human participant admission. The one-second media-policy barrier returned
  unavailable before the participant committed or main-room media activated.
- The acceptance button becomes the Disconnect action. Its quiet variant uses white
  text, while the shared hover rule uses a white background; Chrome computed both
  as the same color after clicking. The contrast correction is a separate checkpoint.

## Investigation limits

- Archived admission metadata does not identify which browser claimed the token.
- Private preparation does not emit a main-room connection fact, so absence of that
  fact alone is not evidence that WebRTC never attached.
- Browser CLI text waits stalled its command queue; subsequent checks use direct
  snapshots and bounded commands instead.

## Correction

- The failing enforcer was SpeechToText. Every policy revision synchronously closed
  and reconnected its Deepgram provider session inside the one-second barrier.
  The real TLS/WebSocket handshake exceeded that deadline. Increasing the barrier
  timeout would still couple participant admission to external network latency.
- Retain per-revision provider sessions, but reconnect in a dedicated supervised
  connector. The capability immediately clears the old session and installs its new
  policy; audio is denied while the replacement is pending. Connector readiness and
  provider callbacks share one sender, so callbacks cannot overtake session binding.
- A later revision cancels a pending or active connector and its linked transport.
  Owner links/monitors keep these workers within the capability's lifetime; losing
  the current worker still fails the capability under the existing room policy.
- The focused regression held provider startup until explicitly released. Before
  implementation, the next policy application returned unavailable. Afterward it
  acknowledged without the handshake, cancelled a superseded start, rejected old
  callbacks, resumed with the newest revision, and cleaned up the worker/transport.
- Existing session-pinning checks now await provider readiness before pushing audio.
  The transfer/policy subset passes 15 checks; the real two-peer Gateway transfer
  check passes and decodes audio in both directions.
- Full umbrella verification with MIX_ENV=test passes formatting, warnings-as-errors
  compilation, strict Credo, unused dependencies, and 997 tests (15 integration
  cases excluded). No dependencies added.
- A separate development VM using real Gemini and Deepgram and two Chrome tabs now
  passes both policy barriers, promotes main media, and reports Main room active.
  The caller retains Disconnect and does not return to Create room after acceptance.
  Both peers remained connected for more than two minutes with inbound and outbound
  RTP packets on each side. Synthetic microphones were used; no subjective phone audio-quality claim is made.

## Separate finding

A fresh diagnostic boot encountered an existing tenant identifier mismatch:
`PublicId.tenant_key/0` can generate a leading hyphen or underscore, while runtime
commands require an initial alphanumeric character. That VM could prepare calls but
could not start them. Restarting only the diagnostic VM generated a valid tenant and
unblocked the transfer verification. This unrelated identifier contract is unchanged
by this checkpoint.
