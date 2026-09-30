# Cartesia turn STT

## Starting evidence

Cartesia TTS now has selected live evidence and scoped startup/UI verification.
STT remains unimplemented and absent from the manifest. This next checkpoint
will use the reviewed automatic-turn Ink 2 protocol; gateways remain deferred.
Research started while the TTS root acceptance process was running. No new
recognition connection or billable request has been made in this checkpoint.

## Provider boundary review

The official [turn guide](https://docs.cartesia.ai/use-the-api/stt/turns)
distinguishes semantic start, cumulative stable transcript updates, tentative
end, resume and definitive end. Updates replace the stored full transcript;
they must not be concatenated. A new local turn reference begins only at a
start event. Resume invalidates an eager end rather than completing a turn.
Continuous audio must include silence. Finite input requires a close command
followed by draining remaining recognition before socket retirement.

The endpoint-reference fetch timed out twice and its Markdown URL was unavailable.
The official Python SDK was retrieved successfully through GitHub's public tree
API and raw source, resolving the wire-field questions without a provider call.
[Automatic-turn resource](https://github.com/cartesia-ai/cartesia-python/blob/main/src/cartesia/resources/stt/auto_finalize.py),
[response schema](https://github.com/cartesia-ai/cartesia-python/blob/main/src/cartesia/types/stt/stt_auto_finalize_websocket_response.py).

The resource uses `/stt/turns/websocket`, mandatory `model`, `encoding` and
`sample_rate` query parameters, and the client's version/authentication headers.
The SDK's default version is `2026-08-14` and authentication is a Bearer API key.
`connected` has a connection request ID; every turn event carries that same
request ID. There is no provider turn ID in the schema, so turn references must
be locally minted. Start and resume have no transcript; update, eager end and
end carry full cumulative text. Close is a JSON text command; PCM travels in
binary frames. Initial model selection is `ink-2`.

The SDK and guide disagree on default eager/end threshold numbers. Initial
configuration should omit optional threshold tuning and use server defaults;
it must not encode one source's defaults as an asserted compatibility guarantee.
Provider-specific tuning can be added with its own reviewed contract later.

## Related unresolved contract

The official [ElevenLabs commit guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
still describes commits as transcription segments. Manual mode can commit
automatically after roughly 36 seconds; VAD mode commits after a silence
threshold. A conversational integration must establish the boundary cause and
speech-start evidence instead of treating every committed segment as turn end.
This is a pending ElevenLabs design question, not a blocker on Cartesia.

## Next work

- [x] Verify automatic-turn request and response fields from primary SDK sources.
- [x] Write configuration and cumulative transcript/lifecycle red tests.
- [x] Implement provider-owned protocol state and bounded socket/session ownership.
- [x] Verify readiness, eager end/resume, final turn, close/drain and failure locally.
- [x] Wire scoped startup and Console capability metadata after local acceptance.
- [x] Run one selected paced speech/silence live check with the reusable public fixture.

## Console UI documentation handoff

The Operate extension adds Cartesia STT alongside TTS in `setupCatalog.json`:
both capabilities and sample defaults, `ink-2` recognition, the existing
`sonic-3.6` synthesis default, and “Transcribe with Ink and speak with Sonic.”
It uses the incumbent scoped platform/tenant setup and one masked API key.
Save remains available with explicit guidance that credential testing is
unavailable and a call can verify the saved key.

The documenter inspected the four blank-key browser captures under
`.impeccable/review/`: `cartesia-stt-platform-desktop.png`,
`cartesia-stt-platform-mobile.png`, `cartesia-stt-tenant-desktop.png`, and
`cartesia-stt-tenant-mobile.png`. Desktop is 1440×1000; mobile is 390×844.
Platform setup displays both speech capability badges; tenant Services retains
its existing provider selector and credential form. Controls and guidance fit
the captured widths. The fresh finish review returned **ship** with no material
fixes within this scope; the implementation handoff reports 209 frontend tests
passing, zero failures, and green TypeScript/lint checks.

These captures do not establish saved, loading, error, or inheritance behavior.
`PRODUCT.md`, `DESIGN.md`, and `.impeccable/design.json` contain no Cartesia
provider inventory requiring an update, and the extension preserves the
Operator’s Bench palette, typography, and layout. The review captures are
verification evidence rather than shipping raster assets.

## Implementation and red-green evidence

- Configuration/decoder and pure turn-state tests first reported five failures
  for absent Cartesia modules. Their implementation then passed five checks.
  Bound UTF-8 messages and cumulative transcripts; maintain one local turn,
  stable connection identity and eager/resume/definitive-end transitions.
- Session tests first reported twelve failures for the absent session. After
  implementation, five failures exposed a fixture mistake: finite finalization
  is the STT provider callback, not a public `Session.finish_input/1` API.
  Tests were corrected to the existing boundary; twelve then pass. No new public
  Session operation was added. The checks cover readiness, drain idempotence,
  final-turn preservation, unexpected/abnormal close, EOF, missing final turn,
  timeouts, status redaction and hard-killed provider/socket cleanup.
- Use the existing shared speech socket for raw PCM and JSON framing. Its normal
  peer-close observation is combined with accepted finite close and completed
  turn state; EOF alone cannot prove completion. A loopback test exercises a
  final start/end/close in one coalesced socket delivery. This passes alongside
  the raw-frame/close-command check: two checks, zero failures.
- Scoped-call tests failed at the absent STT manifest and unsupported Call Spec
  selection before registration/runtime wiring. They now prove closed public
  options, private config and usage identity. Persisted Console tests extend
  platform inheritance, tenant override and removal fallback to both STT/TTS.
  Initial fixture assertions assumed `CapabilitySelection.new/3` did not already
  validate selections and that every participant has STT; corrected them to its
  actual admission error and the single non-nil human runtime.
- Compiled startup launches a real semantic allocation using a synthetic wire:
  acknowledged ready, private key, admitted PCM and correlated final text pass.
  The focused Cartesia/startup group reports 45 tests, zero failures with local
  integration included. Console scoped/API group: 13 tests, zero failures.
- Frontend tests first reported three failures for missing STT capability/default
  and badges. Updating the existing setup catalog makes all 209 frontend tests
  pass; TypeScript and lint also pass. No new credential input or transport hook.

## Selected live evidence

Command (only the selected Cartesia recognition file):

```shell
PGHOST=/var/run/postgresql bin/test-live-providers --only live_cartesia apps/vxpipe_call_engine/test/integration/cartesia_speech_to_text_test.exs
```

One test passed in 9.4 seconds, seed 791470, on 2026-09-30. It opens one Ink 2
connection, reuses the committed 4.16-second public sample including its silence,
adds four seconds of paced silence, and bounds total input below ten seconds.
The final word `telescope` survives semantic turn end and close/drain completion.
No new TTS sample was generated; no retry or second provider request was run.
This is direct protocol evidence. Encrypted service publication and compiled
startup are verified locally with synthetic keys, not a live whole-room claim.

## Repository gates

- [x] `mix format --check-formatted`
- [x] `mix compile --warnings-as-errors`
- [x] `mix credo --strict`: 1,154 source files, no issues.
- [x] `mix deps.unlock --check-unused`
- [x] `bin/verify-lean`: model build, oracle check and Elixir replay pass.
- [x] `mix test --seed 149103`: the terminal rerun passes all 2,922 reported
  tests, zero failures and 74 exclusions, including 1,718 CallEngine,
  520 Gateway and 193 Console checks. The initial same-seed run had one
  Telnyx custom-URL/destination-loss recovery-speech harness failure.

These gates belong to this checkpoint. ElevenLabs and final shared milestone
acceptance remain open. Gateway routing implementation is still deferred.

## Root failure follow-up

The seed-149103 umbrella run found a Gateway failure in Telnyx's existing
custom-URL/destination-loss phone harness: `PhoneHandoffAssertions.recovery/2`
received its failure/continuation evidence, but timed out waiting for source
recovery speech. This is different from the earlier preparation-progress timeout.
No Cartesia transport is used by that harness. The same-seed selected destination
case passed in 2.3 seconds; the same-seed whole harness also passed thirteen
checks. The subsequent full same-seed root run passes with zero failures.
No deadline increase or runtime repair was applied. These passes accept this
checkpoint but do not establish the intermittent failure's cause or repair.
A separate phone-recovery labnotes file records a concrete zero-PCM synthetic
acknowledgement hypothesis for a focused regression checkpoint.
