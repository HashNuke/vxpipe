# Final speech acceptance

## Scope

Complete checkpoint H of `docs/milestones/simpler-speech-integrations.md`: remove the remaining
open host configuration shape, verify every consumer/credential boundary, run bounded end-to-end
and load acceptance, update durable documentation, inspect the rendered sample when available,
audit simplification and pass the root gates. Runtime speech execution was already cut over in C/E;
H changes startup validation, fixtures, documentation and acceptance evidence.

## H1 configuration migration

- Red: `inline_activation_test.exs` supplied the former top-level speech provider/private keys.
  The plan validated successfully, proving the host boundary still accepted the obsolete shape.
- Green: `CapabilityCatalog.speech_adapters/1` now supplies the closed STT/TTS module sets.
  `PlanStartup` accepts only `[providers: %{registered_session_module => provider_settings}]` and
  validates the exact settings for each built-in session. Unknown modules, top-level provider keys
  and extra provider fields return the existing safe unsupported-call-plan error.
- `config/config.exs` now represents disabled speech as empty provider maps. `config/dev.exs` and
  Engine, Persistence and Gateway fixtures use only registered provider maps. Session-level
  `options`/`private` remain deliberate internal provider input, and Call Spec `provider_options`
  remains the public provider-specific selection field.
- Final source audit removed the unused `Readiness.Provider.initial_status/1` probe for the retired
  `readiness_mode/0` callback. The live fail-closed connection transition remains covered.
- Focused Call Engine migration selection: 185 tests, zero failures, seed 0. The initial compile
  exposed stale local `default_stt/default_tts` bindings; the test now asserts the exact registered
  modules instead.

## H2 activation boundaries

- Calls call-spec/admission checks: 19 tests, zero failures.
- Persistence runtime/opening/scoped/inline checks, including the tagged destination-activation
  lane: 38 tests, zero failures.
- The first Persistence pass had six failures because three fixtures still constructed the removed
  top-level host shape. Moving those fixtures to provider maps made the unchanged credential cases
  green. The final selection covers tenant/platform scope, fresh activation lookup, running-session
  snapshots, opening cache scope, private destination briefing and source restoration.

## H3 end-to-end and provider checks

- Direct PCM room coverage was part of the 185-test Engine selection. Its final focused check starts
  native Morse playback, reports 20 ms of progress, interrupts it with a second encoded caller
  utterance, verifies the replacement command/correlation identity and decodes the replacement
  output to `OK`; one test passes in 1.7 seconds. Typed/spoken interruption tests also finish the
  replacement request and require both `AgentSpeechStarted` and `AgentTurnCompleted`; five focused
  interruption tests pass.
- Native WebRTC boundary selection: 29 tests, zero failures with two cases at a time. The isolated
  real Morse WebRTC human-transfer case passed in 131.1 seconds. The five-participant WebRTC case
  failed once only inside an overly broad concurrent Gateway command; the command was stopped to
  avoid unnecessary resource pressure. The exact case then passed alone in 121.9 seconds. This is
  not reproducible evidence of change-caused instability.
- Outbound phone-transfer media checks: six tests, zero failures. A combined serial Telnyx/Twilio
  startup selection produced one missing-wait observation in the Twilio model case. That exact tag
  passed twice in isolation, including the expected 48 kHz normalized ingress, so no migration
  regression was established.
- Hosted Deepgram TTS passed both the native semantic-session test and full WebRTC/RTVI playback
  test: one test each, zero failures. `DEEPGRAM_LIVE_AUDIO` was unset, so the hosted STT lane could
  not be run honestly; the already-accepted C hosted STT result remains the latest external evidence.

## H4 documentation and rendered check

- Architecture, development, interruption, barge-in, readiness, inline selection, transport
  privacy and complexity documents now describe the scoped semantic-session boundary, closed host
  registry, provider-private wires, complete replacement turns and retained domain monitors.
- The running development endpoint rendered the room-creation page correctly in an isolated Chrome
  session at 1440×1000 with no page errors. Creating a room returned
  `durable_sample_disabled`, then the explicit development fallback returned
  `unsupported_call_plan` because no tenant speech credential was available to that path. Connected,
  speaking, interrupted and replacement UI states were therefore unavailable; no rendered or audible
  claim is made for those states. Automated real PeerConnection tests cover their engine/gateway
  behavior, but do not replace this recorded browser limitation.

## H5 bounded reliability and latency evidence

All final diagnostics used `ERL_FLAGS='+S 4:4'`; no run used more than half of the development
machine's eight cores. A first TTS request for four workers was rejected by the harness because its
own cap is half of enabled schedulers; the accepted run used two workers.

- Scoped lifecycle/startup/cancellation selection: 33 tests, zero failures. It verifies that every
  execution child descends from the explicit local scope, provider/allocation/shared failures stay
  within their specified boundary, siblings progress and replacement is explicit.
- Bounded Morse STT: three repeats at one and four scopes, two warmups and 20 measured rounds per
  worker. All 300 turns passed. One-scope first-transcript p95/p99 was 119/127 µs and turn-end
  p95/p99 was 224/239 µs. Four-scope first-transcript p95/p99 was 269/352 µs and turn-end p95/p99
  was 305/335 µs. The per-repeat distributions were:

  | Repeat | Scopes | Turns | First transcript p50/p95/p99 µs | Turn end p50/p95/p99 µs |
  | --- | ---: | ---: | ---: | ---: |
  | 1 | 1 | 20 | 104 / 117 / 124 | 201 / 224 / 225 |
  | 1 | 4 | 80 | 157 / 238 / 259 | 254 / 314 / 335 |
  | 2 | 1 | 20 | 105 / 119 / 123 | 208 / 229 / 239 |
  | 2 | 4 | 80 | 171 / 335 / 357 | 226 / 305 / 325 |
  | 3 | 1 | 20 | 104 / 116 / 127 | 198 / 218 / 221 |
  | 3 | 4 | 80 | 156 / 212 / 377 | 250 / 294 / 340 |

- Bounded Morse TTS: two workers × three requests, six successes. First-audio p50/p95 was
  181/6,878 µs, generation-completion p50/p95 was 47,468/52,550 µs, and controlled sink-planned
  completion p50/p95 was 902,080/909,523 µs. The final value includes the PCM duration and is not
  network or physical playout latency. Each row below is one successful request:

  | Worker | Round | First audio µs | Generation complete µs | Planned sink complete µs |
  | ---: | ---: | ---: | ---: | ---: |
  | 1 | 1 | 6,878 | 52,550 | 909,523 |
  | 1 | 2 | 181 | 47,472 | 901,275 |
  | 1 | 3 | 198 | 45,091 | 902,080 |
  | 2 | 1 | 6,870 | 52,536 | 909,345 |
  | 2 | 2 | 181 | 47,468 | 901,253 |
  | 2 | 3 | 181 | 45,094 | 902,127 |

- Controlled Deepgram TTS session: two workers × three requests, six successes. Completion
  p50/p95 was 201/7,200 µs and settlement p50/p95 was 266/9,826 µs. The private wire is controlled;
  hosted interoperability is recorded separately above. Individual trials were worker 1:
  7,200/9,826, 75/102 and 234/282 µs completion/settlement; worker 2: 7,190/9,771,
  201/266 and 45/64 µs.
- Paced native WebRTC checks passed in H3. Earlier accepted D/E 1/8/32-scope cancellation and
  handoff reports remain the larger fault/burst evidence; H intentionally did not repeat those
  resource-heavy runs because H changes no live session execution.

## H6 simplification audit

Relative to `main`, the cutover deletes nine production modules: the old STT connector, four
public provider/transport behaviour modules and four Morse facade/JSON transport modules. Those
behaviours exposed 23 callback declarations. The application also deletes the global STT connection
and TTS output task supervisors. Net source lines increase because scoped ownership, native
providers, tests and explicit contracts are new; moved code is not counted as eliminated complexity.

Retained owner/lease/consumer/provider monitors enforce authority, attribution and current-generation
failure behavior. Readiness, policy, usage, audio credit and confirmed playback remain explicit
domain responsibilities. OTP supplies tree lifetime and significant-child shutdown. No global speech
executor, compatibility execution path, automatic reconnect, replay or custom recovery coordinator
remains.

## Completion review

The required GPT-6 Astra xhigh review found no remaining P1/P2 runtime blocker after two findings
were repaired: every registered provider entry is now validated before provider selection, and the
README embedded configuration uses only the accepted provider-map shape. Its remaining acceptance
caveat was the lack of one combined direct-Morse room interruption/replacement check; that check is
now implemented and passes as recorded in H3. The final review confirmed the caveat is closed and
the durable per-repeat load evidence matches the reviewed reports.

The first strict Credo gate found that the new validation pushed `PlanStartup` to 805 lines.
After its behavior was green, the closed adapter settings validation moved into
`CapabilityCatalog`, the cohesive owner of provider registration and selection. `PlanStartup` is
747 lines after the refactor, and the nine focused configuration/readiness tests remain green.

The first final root-suite rerun found one ordering race in the synthetic semantic TTS test. The
probe emitted provider completion before receiving its existing channel-credit acknowledgement;
the runtime correctly rejected that premature terminal with `{:error, :output_pending}`. The exact
unfixed test reproduced the failure on repeat 19. Waiting for the project-owned
`usage_probe_audio_credited` acknowledgement made the same test pass 100 consecutive repeats. No
runtime behavior, retry or sleep changed.

Final root gates with `ERL_FLAGS='+S 4:4'`:

- `mix format --check-formatted`: pass.
- `mix compile --warnings-as-errors`: pass.
- `mix credo --strict`: pass after the SRP refactor, 1,007 files and no issues.
- `mix test --seed 0`: 1,957 tests, zero failures, 42 excluded. The Gateway's real-time media lane
  took 401.2 seconds; the full command completed successfully without concurrent load.
- `mix deps.unlock --check-unused`: pass.
