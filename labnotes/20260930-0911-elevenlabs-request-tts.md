# ElevenLabs request TTS

## Starting scope

Cartesia STT was accepted and pushed as 28043981. The independent phone-recovery
fixture repair is running root acceptance. ElevenLabs has a live API-key placeholder and can reuse the shared credential
schema; its provider manifest and speech registration are still absent. AI gateway implementation remains
deferred. No ElevenLabs request has been made in this checkpoint.

## Primary-source request review

The [HTTP stream reference](https://elevenlabs.io/docs/api-reference/text-to-speech/stream)
uses `/v1/text-to-speech/{voice_id}/stream`, `xi-api-key` authentication,
`output_format` in the query, and text/model in the JSON body. Its example voice
is `JBFqnCBsd6RMkjVDRZzb`; the
[quickstart](https://elevenlabs.io/docs/eleven-api/quickstart) names it George.
PCM at 44.1 kHz has a documented subscription restriction; use 16 kHz for the
selected bounded acceptance test and retain existing media negotiation.

The [official SDK output enum](https://github.com/elevenlabs/elevenlabs-python/blob/main/src/elevenlabs/text_to_speech/types/text_to_speech_stream_request_output_format.py)
includes raw PCM at 8, 16, 22.05, 24, 32, 44.1 and 48 kHz. The first slice should
advertise only reviewed negotiated rates rather than every listed codec.
Authentication belongs in the private request headers, never query credentials.

The [model catalog](https://elevenlabs.io/docs/overview/models) still identifies
Flash 2.5 as economical. It documents v4 through Text to Dialogue and v4 Turbo
through its WebSocket; the quickstart now shows v4 on ordinary TTS. Those sources
are inconsistent about transport availability. Do not infer all newer model
families share the established phrase HTTP contract. Use Flash 2.5 for one
short selected live request and define reviewed HTTP model admission explicitly.

## Ownership decision

Reuse `Speech.RequestTTSSession` for complete-phrase task ownership, credit,
cancellation and local readiness; keep ElevenLabs configuration/request parsing
in its provider directory. Reuse bounded `Speech.PCMStream`, but do not introduce
a provider registry inside a transport or route through Cartesia modules.
Wire protocol construction remains vendor-owned. Final HTTP success is generation
completion after accepted credit, not audible playout. Reject unsuccessful,
empty, misaligned, over-limit or unsupported-format responses without retry.

## Work sequence

- [x] Inspect primary HTTP, SDK PCM-format and model documentation.
- [x] Write configuration/session contract tests and confirm the missing adapter fails.
- [x] Implement closed public options and the private request/session adapter.
- [x] Verify fragmented PCM, errors, credit and cancellation at owning boundaries.
- [x] Verify compiled room startup and encrypted platform/tenant publication.
- [x] Inspect rendered Console setup and pass focused frontend checks.
- [x] Run one selected, bounded live synthesis with the shared fixed model/voice.
- [x] Record all root/Lean gates and commit a coherent checkpoint.

## Related protocol research

[Speech Engine](https://elevenlabs.io/docs/overview/capabilities/speech-engine)
adds recognition/synthesis around a caller-owned LLM using a server-side upstream
connection. It differs from hosted ElevenAgents conversation and standalone
Scribe. Investigate its actual upstream wire and direction before treating it
as an STT turn-authority solution; the overview is not conformance evidence.
Standalone Scribe's documented commits still finalize segments, with no speech
start or boundary-cause event in the current reference. Keep the pending STT
question explicit while progressing independent synthesis.

## Initial red-green checkpoint

Three configuration/session checks first fail for absent ElevenLabs modules.
Seven selected loopback HTTP checks independently fail for the absent private
configuration/request adapter. Implementation of provider-owned TTS, TTSSession
and TTSRequest makes all ten checks pass, 0.4s, seed 548423. No capability
registration or UI support is claimed yet; the next red gate is scoped compiled
startup admission. No billable ElevenLabs request has been made.

The initial public phrase contract accepts Flash 2.5, Multilingual v2 and v3,
path-safe bounded voice IDs, and raw mono signed little-endian PCM at 8/16/24/48
kHz (default 16 kHz). It rejects duplicate/unknown options and private hooks,
bounds text to 1,000 characters / 4,000 UTF-8 bytes, disables retries/redirects,
and uses the existing PCMStream response bound. The request adapter owns its
status/content-type handling; session lifecycle remains shared.

## Temporary checkpoint isolation

The new, untracked ElevenLabs `lib` and `test` directories are temporarily
preserved in the temporary `vxpipe-elevenlabs-pending-checkpoint` directory
(`lib` and `test` children) while the
Gateway fixture checkpoint runs its root gate. Restore them to the same provider
directories after that checkpoint commits. The source and ten green tests are
retained intact. They are not registered, committed or live-accepted yet.

Speech Engine's actual upstream reference confirms reversed connection direction:
ElevenLabs connects to a publicly reachable developer WebSocket. That cannot
be substituted for the standalone outbound Scribe stream without new ingress
and authenticated conversation ownership. Its semantic user transcript events
are interesting for a future separately owned integration, not existing STT
conformance. [Upstream wire](https://elevenlabs.io/docs/api-reference/speech-engine/speech-engine-upstream).

## Checkpoint restoration

Gateway fixture checkpoint 1ffb1241 passes all five root gates: 2,924 reported
tests, zero failures, 74 excluded, seed 149103. The pending ElevenLabs files were
restored to their original provider source/test directories after that commit;
all five file hashes match their preserved copies. Its initial ten local green
checks remain the current ElevenLabs evidence. Registration, compiled scoped
startup, Console, live acceptance and final gates are still pending.

The reviewed standalone Scribe event list does not add a speech-start event or
commit cause. ElevenAgents separately exposes `vad_score` and whole-utterance
`user_transcript`, plus client tools and response correction. Those belong to
hosted conversation, not standalone Scribe; they do not resolve Scribe's
conversational turn authority by renaming transcript segments.
[Scribe event reference](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference),
[Agents client events](https://elevenlabs.io/docs/eleven-agents/customization/events/client-events).

## Compiled scope and Console acceptance

The previous goal turn is classified as progress: it committed/pushed the
Gateway fixture checkpoint and completed all root gates. This turn resumes the
full provider goal with its ElevenLabs work, rather than treating that checkpoint
as completion of the provider milestone.

Three new inline admission checks first report 19 tests, two failures: the call
spec rejects ElevenLabs because its TTS capability is absent. Registry tests
then report 6 tests, three failures for the absent manifest/catalog/credential
schema. Registration and vendor-specific compiled configuration make both files
green: 29 compiled/config/shared request-session checks and 6 registry checks,
zero failures. The compiled session proves scoped private credentials, public
voice/model/rate, PCM credit, measured usage and confirmed playout settlement.

Persisted Console acceptance passes 13 checks across service save/catalog and
the new ElevenLabs publication case. The latter verifies platform inheritance,
tenant override, cache identity change, private-key redaction, and restoration
after removing the tenant override. It exercises existing encrypted persistence
and compiled startup, without making an upstream request.

Frontend acceptance checks first report 51 tests, seven expected failures for
missing catalog, private-key form, unavailable probe, saved inventory and scoped
modal support. The extension reuses the incumbent Operate surface and advertises
only implemented phrase TTS. One private API key is the service input; model and
voice remain call settings. Full frontend tests, TypeScript and lint are running.
No public credential-validation capability or live synthesis is claimed yet.

## Focused frontend and live evidence

The first full frontend run reports 215 checks with one failure: the existing
onboarding provider-picker expectation omits the new installed provider. Updating
that mechanical inventory expectation gives 215 passing checks, with TypeScript
and lint clean. During the rendered pass, the synthetic tenant fixture is found
to assign a validation timestamp on any successful save. A focused ElevenLabs
save check reproduces that false claim before implementation (three tests, one
failure). Credential creation now stores no validation timestamp; saving alone
does not prove upstream validation. The full frontend suite then passes 216
checks across 33 files, with TypeScript and lint still clean.

Seven selected loopback HTTP checks pass, seed 396340. They cover fragmented PCM,
private request construction and failed/unsupported/empty/truncated response
handling without a billable call. Shared request-session tests and compiled
startup supply credit, cancellation and settled usage evidence at their owning
boundaries.

Exactly one live phrase, `Hello from Vxpipe.`, uses the common fixed Flash 2.5,
George and 16 kHz selection. The provider-specific file reports one test, zero
failures in 1.4 seconds, seed 329651. It verifies credited PCM and locally
measured input characters/generated bytes, bounds audio to ten seconds and
observes settlement within 30 seconds. No output device is attached; confirmed
generation/zero-playout settlement does not claim the audio was heard. The runner
loads credentials only in its child process; the private environment file was
neither read nor changed. This successful live request is not repeated.

## Rendered evidence

One bounded Chrome pass inspects blank-key ElevenLabs forms at 1440x1000 and
390x844 for both platform and tenant scope. Captures are under
`.impeccable/review/elevenlabs-{platform,tenant}-{desktop,mobile}.png`. Each valid
capture is opened before the fresh finish-review handoff. Storybook is synthetic
and nonpersistent; no upstream validation or billable request occurs there.
Test credentials is disabled with existing unavailable guidance; Save remains
independent. Other saved/error/inheritance states have local checks and are not
claimed as rendered acceptance.

Chrome initially requires `--no-sandbox` in this container. A generic selector
wait times out despite a ready accessible snapshot; fresh element references
work. Absolute screenshot paths avoid the CLI's relative-path fallback to its
temporary screenshot directory. Hot reload resets the tenant story between
captures; a wrong-state desktop capture is discarded and replaced with the
settled ElevenLabs-selected form before review. These are verification-tool
limitations, not provider protocol failures.

The fresh finish reviewer returns `ship` for these four valid captured forms,
with five contract sections and no material fixes. Its verdict does not establish
production persistence or rendered saved/error/inheritance states.

## Repository acceptance

All five root completion gates pass: format checking, compilation with warnings
as errors, strict Credo, the full default test suite, and unused-dependency
checking. The seed-149103 root run reports 2,931 tests, zero failures and 82
exclusions: MCP 37, Providers 28, AgentRuntime 99, CallEngine 1,724, Calls 120,
Gateway 522, Artifacts 20, Persistence 187 and Console 194. The test process
terminates successfully. No billable live test runs in that default lane.

Lean builds all four jobs, checks oracle drift and passes its one Elixir
transition replay test, seed 671109. No new dependency or lockfile change is
introduced.

During final source review, malformed-response HTTP checks are tightened to
record unexpected PCM in a message rather than raising inside the consumption
callback: the adapter intentionally rescues callback failures, so an assertion
there could be swallowed. This is a test-only correction. Its selected local
integration lane passes seven checks, zero failures in 0.5 seconds, seed 427276;
format and strict Credo are checked again. No passing live call is repeated.

This accepts the coherent ElevenLabs TTS checkpoint. Standalone STT turn
authority and hosted agent STS remain pending; no complete provider-expansion
milestone or gateway implementation is claimed.

## Documenter reconciliation

The documenter compares PRODUCT.md and DESIGN.md with the credential form,
service modal, provider catalog, service avatar, fixture and incumbent admin/setup
styles. ElevenLabs adds catalog data and reuses the existing input, action,
capability tag and avatar patterns. No new CSS, shared token, responsive model or
durable visual-system rule is introduced. DESIGN.md already describes the
Operator's Bench palette, type hierarchy, flat materials, compact fields and
state agreement needed by this extension; it and the design sidecar remain
unchanged. The provider's single private API key, public call model/voice and
TTS-only admission remain local product contracts, not new global design rules.

The finish-review handoff reports SHIP for the four blank-key platform/tenant
captures at 1440x1000 and 390x844, with incumbent hierarchy, materials, privacy,
TTS-only truth and responsive fit passing. Saved, error and inheritance states
have local tests only; this documenter source pass adds no rendered verification
claim. The handed-off frontend evidence is 216 passing tests plus clean
TypeScript and lint. An unavailable credential probe and an independent Save
remain explicit; a saved credential is not canonized as successful validation.
