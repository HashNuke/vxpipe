# Add Scribe Live

## Research and scope

- Official ElevenLabs documentation, checked 2026-11-14, lists `scribe_v3_live`
  on the existing realtime WebSocket endpoint, with the same API-key header,
  PCM input and partial/committed transcript events as v2. Manual and VAD commits
  remain supported. V3 also supplies `turn_probability` on partials.
- Sources: [API reference](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime),
  [commit strategies](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies),
  [release announcement](https://elevenlabs.io/blog/scribe-v3).
- Add V3 alongside V2, retaining existing default choices. No new SDK, process,
  connection configuration, credential type or state machine is needed.
- The existing decoder hardcoded the v2 acknowledgement. Pass the selected model
  through both manual and continuous session socket options and validate that
  model at readiness; do not accept an arbitrary supported model instead.
- Optional provider turn prediction/multilingual mode/diarization are not enabled
  by selecting V3. The separate turn-detection milestone owns endpoint changes.
  A partial probability alone is not published as an endpoint.

## Verification

- Initial focused tests: 15 total, three expected failures for the missing model,
  rejected call-spec selection and v3 readiness. After implementation all pass.
- Engine: 71 focused checks pass, including the local loopback WebSocket lane,
  Scribe decoding, model selection, both existing session modes and model catalogs.
  No provider network is involved in the loopback server.
- Console: 15 focused checks pass. V2/V3 published specs each prepare with omitted,
  disabled and enabled local onset VAD, inherit platform credentials, use tenant
  overrides and report the selected model in usage identity. Public catalogs and
  authorization remain covered by the existing endpoint checks.
- Frontend: 25 focused setup/inspector checks pass with both model descriptors.
  Chrome preview at 1440x1000 shows both options and allows selecting V3. The
  selected V3 label also fits the 390x844 mobile settings sheet. The
  preview uses the real editor with synthetic HTTP responses in an environment-free
  mirror; it is not a live-provider or hosted acceptance test.
- Root format, compile with warnings as errors, strict Credo and unused-dependency
  checks pass. No turn/source state-machine transition changed, so the Lean lane
  was not rerun. No full test suite was run.
- Environment files were not read. No live provider, paid speech or telephony
  tests are authorized or run. No deployment.
