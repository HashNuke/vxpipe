# Morse configured-room acceptance

Continuation of checkpoint F after the provider/service implementation in
`8faa2c4e`. This checkpoint verifies the actual Console persistence and CallEngine
boundary against the unchanged Go server at `b922e71`, using loopback port 18796.

- Added an opt-in `live_morse_code_api` Console integration test. The first run
  rejected entry-caller fields under the newer schema; corrected the fixture to
  the existing supported `20260915.01` source shape. The next run failed because
  the controlled output recipient did not yet exist. Added that test helper and
  optional output/send-text support to Console's existing speech connection.
- The saved encrypted platform credential and published call now produce opening
  `SOS` and conversational `TEST` through ordinary room output using actual HTTP
  streaming from Go. Vxpipe's independent decoder verifies complete PCM. Completion
  waits for explicit recipient playback acknowledgement.
- A deliberately blocked sink retires its first turn on interruption, releases
  pending delivery, accepts replacement synthesis and never completes the retired
  turn. Room shutdown is observed with a monitor. This proves an embedded PCM
  recipient boundary; no WebRTC, browser microphone or hosted audio is claimed.
- Added HTTP-origin observations through Finch's documented request telemetry,
  copying only scheme/host/port/path. All four requests target the configured Go
  TTS route. Public-event inspection initially failed on an empty capture; added
  optional event copies to the connection fixture, then verified nonempty events
  contain no synthetic compatibility key. The complete live test passes.
- Added runtime-loader acceptance for development's local default, production
  configuration loading without a Morse origin, selected-provider failure with
  that missing origin, and explicit HTTPS/WSS configuration. All seven runtime
  configuration tests pass. The existing saved-plan test separately proves actual
  PlanStartup failure when the configured origin is absent.
- Agent-browser/Headless Chrome renders the real editor inspector at 1280×900
  and 390×844. Selected `morse_code_api`, saw `MorseCodeApiTTS` and the Morse 700 Hz
  voice, and inspected both screenshots. Service success/unavailable states were
  already rendered in F's implementation checkpoint. One stale option reference
  required a fresh snapshot after a Storybook rerender; selection then worked.
- The first Storybook launch used the assets directory and failed to find the
  root configuration. Relaunching from the repository root succeeded. Browser,
  owned Storybook listener and owned Go server were closed after inspection;
  both server handles exited zero following SIGTERM.
- The first complete umbrella run passed CallEngine (2,173), Gateway (603) and
  all other applications except Console's outdated exact provider inventory.
  That assertion is corrected in `8faa2c4e`; 14 focused Console service/activation/
  Scribe-room regressions pass with one hosted test excluded. The new full run
  is active and has passed CallEngine again. Do not infer a final full-suite pass.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  checks pass for the room harness; the additional runtime test also passes its
  focused lane. No speech state machine or source-cutover implementation changed.
  Full frontend evidence remains 98 files / 758 tests, all passing.

F's functional acceptance is complete; the milestone and index now show A–F,
six of nine checkpoints. G (STT), H (full compatibility/performance), I (deployment
handoff/hosted cutover) and milestone-wide final gates remain incomplete. No push
or Railway deployment was performed.
