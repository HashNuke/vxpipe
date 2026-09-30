# Cartesia request TTS

## Scope and decision

Implement Cartesia complete-phrase TTS through `/tts/bytes`, keeping its
configuration and HTTP response handling under `Vxpipe.Providers.Cartesia`.
Extract Google's existing owned request task lifecycle into
`Speech.RequestTTSSession`. This narrow lifecycle owns credit, cancellation and
task cleanup; it does not generalize WebSocket protocols or upstream routing.
Google retains its own configuration and SSE/audio decoder. This avoids copying
the same request lifecycle into each complete-phrase provider. Cartesia STT and
ElevenLabs remain separate pending parts of the milestone; gateways remain
deferred.

## Red-green evidence

- Original Google request-session baseline: 3 passing tests. The same three
  pass after the mechanical lifecycle extraction.
- Cartesia public/private configuration: 3 tests fail with undefined modules,
  then pass with model/UUID/rate validation, versioned request construction,
  bounded text and redacted inspection.
- Raw PCM framing: 3 tests fail with the missing module, then pass with aligned
  fragments, a one-byte carry, bounded chunks/total bytes, and rejection of
  empty or truncated completion.
- Cartesia loopback HTTP boundary: 7 tests fail before the request adapter,
  then pass (`--include integration`). They cover aligned streaming, rejected
  status/content type/redirect/empty/truncated responses and consumer failure.
  Invalid responses expose no audio and do not trigger another request.
- Shared Google/Cartesia session and configuration/framing group: 13 passing
  tests, including credited audio, exact-request cancellation/replacement,
  failure without false completion and request task termination after a killed
  provider. The first generalized run failed because two capability trees had
  the same test supervisor child ID; explicit unique child IDs fix that fixture
  collision. No runtime change was needed for this failure.
- Scoped Cartesia startup initially fails at unsupported call-spec selection
  (2 failures). Registry tests initially fail on missing credential/capability
  metadata (3 failures). After wiring the registry, closed options, credential
  resolution and private runtime configuration, startup/runtime/session/PCM
  group executes 28 tests with zero failures and excludes 7 HTTP integration
  tests. Provider registry: 6 tests, zero failures. Seed 412687 for CallEngine.

## Contracts and review

The live selection is stable `sonic-3.6` and documented stock Skylar voice;
the versioned bytes API uses `2026-08-14`. Raw mono signed little-endian PCM is
negotiated at 8/16/24/48 kHz. Each phrase permits one request, no retries or
redirects, bounded text, bounded response audio, a request deadline and consumer
credit. Usage identity is locally measured; no provider token count is invented.
Only API-key credentials and the implemented TTS capability are registered;
STT and credential probes are not advertised yet.

Primary references: [bytes API](https://docs.cartesia.ai/api-reference/tts/bytes),
[stable model and voice](https://docs.cartesia.ai/build-with-cartesia/tts-models/latest).

## Remaining acceptance

Selected live TTS test passes: one test, zero failures, 0.9 seconds, seed 240015.
It sends one short phrase, with a 30-second deadline and a ten-second PCM
observation bound. Credentials are loaded only by
`bin/test-live-providers`; the private environment file was not inspected.
Compiled startup-to-session checks pass with measured five-character input,
credited PCM bytes and exact playback settlement (15 startup tests pass).
Console persisted publication/inherited key/tenant override/removal fallback and
endpoint checks pass 13 tests. Persistence's scope group passes six tests,
including Cartesia's revoked override failing closed until removal. The Console
test initially called a nonexistent public revoke function; that fixture error
was corrected, and revocation remains tested at its owning Persistence boundary.
Telemetry's Cartesia attribution fails first as `:other`, then passes after its
bounded label is declared (six telemetry checks).

Frontend configuration/inventory/catalog tests fail before the new provider is
added (five failures), then pass 37 focused tests. The complete frontend suite
passes 208 tests. Type checking and lint pass. An exact provider-list expectation
and the exhaustive onboarding fixture mapping needed Cartesia additions.
Root format, warning-free compilation, strict Credo, unused-dependency and Lean
checks pass for the runtime checkpoint. The full root run completes with exit 0,
seed 412687: 2,902 reported tests, zero failures, 72 excluded. Per application:
MCP 37 (3 excluded), Providers 28, AgentRuntime 99 (8 excluded), CallEngine 1,698
(41 excluded), Calls 120, Gateway 520 (7 excluded), Artifacts 20, Persistence 187
(12 excluded), Console 193 (1 excluded). The seven Cartesia HTTP integration
checks also pass separately. The earlier Gateway `after_speech_adoption` failure
does not reproduce in this root run; no causal repair of that intermittent
failure is claimed.

Cartesia STT and ElevenLabs implementation/acceptance remain open. The rendered
Cartesia TTS forms have their independently reviewed evidence below.

## UI review

- [x] Cartesia uses the existing service setup modal at platform and tenant
  scopes. The built surface follows the Operate direction and the incumbent
  Operator's Bench: neutral dark panels, restrained borders, compact labels and
  familiar Cancel, Test credentials and Save actions.
- [x] The provider catalog exposes text-to-speech only, with `sonic-3.6` as the
  default model. The form uses one masked API-key field. Test credentials is
  disabled; adjacent copy explains that credential testing is unavailable and
  that the key can be saved and verified with a call.
- [x] Opened all four supplied captures and confirmed their named scope and
  viewport: platform and tenant desktop at 1440×1000, and platform and tenant
  mobile at 390×844. The blank-key form, provider choice, capability label,
  input focus, actions and tenant ownership notice are visible without modal
  clipping at the captured widths.
- [x] The independent finish reviewer returned **ship** for these blank-key form
  states. Its type, material, ground, provider, capability, input, save, scope,
  responsive and focus checks matched the direction; no material fixes were
  requested. Loading, error, stored-credential and inheritance states were not
  captured and are outside that visual verdict.
- [x] Focused UI/API test coverage describes private-key submission at both
  scopes, unavailable optional credential testing, catalog capability filtering
  and service inventory parsing. These behavior checks complement the captured
  form review; screenshots alone do not establish a completed save.
- [x] Documenter handoff checked `PRODUCT.md`, `DESIGN.md` and
  `.impeccable/design.json` against the built addition. The design references
  contain no specific provider inventory to synchronize. This addition introduces
  no durable visual change, so both design files are preserved.

Capture evidence:

- [Platform desktop](../.impeccable/review/cartesia-platform-desktop.png)
- [Platform mobile](../.impeccable/review/cartesia-platform-mobile.png)
- [Tenant desktop](../.impeccable/review/cartesia-tenant-desktop.png)
- [Tenant mobile](../.impeccable/review/cartesia-tenant-mobile.png)
