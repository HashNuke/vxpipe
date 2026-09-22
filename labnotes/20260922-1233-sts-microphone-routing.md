# STS microphone routing

Implement directly following `docs/sts-input-routing.md`; no delegation,
commits or billable calls. Starting root baseline: 2,153 tests, zero failures
(42 excluded). Preserve the existing dirty worktree and Google production gate.

Begin with a red descriptor contract: STS must declare input PCM independently
of generated output. Morse uses the selected rate in both directions; Google's
input is 16 kHz while output is 24 kHz. Missing or malformed input format must
fail configuration rather than letting Gateway guess from output metadata.

## Directional formats

The initial contract run failed twice as expected: descriptors had no
`input_format` field, and the closed constructor rejected that field. Added
validated mono raw PCM input metadata for STS only. Morse advertises its
selected rate in both directions; Google input is 16 kHz/output 24 kHz. The
descriptor, existing provider-contract and Google session group then passed
42 tests (seed 0).

## Independent admission primitive

The first five `media/sts_ingress_test.exs` checks failed because `STSIngress`
did not exist. Added a temporary, source/capability-monitored ingress with a
closed initial state, track/policy preparation and one credited delivery.
Frame/byte bounds include the outstanding delivery. Identity, format,
membership/route, age and monotonic sequence are checked before admission;
age is rechecked after queueing. Hold and every accepted policy revision clear
the queue but preserve the outstanding credit. Dropped/denied audio is never
replayed on release. An unacknowledged delivery terminates after a bounded
deadline (default 1 second).

Follow-up tests exposed accepted invalid budgets, the missing format query and
microphone bytes visible in process status (12 tests, 3 failures). Validation
now requires positive integer bounds and caps private delivery timeouts at
5 seconds; status/messages/reasons/logs are redacted. Track format queries and
immutable prepared-track binding are covered. Other checks cover stale or
wrong-capability acknowledgements, byte bounds independent of frame bounds,
queued age expiry, ordered policy updates, participant removal, late timers,
source/capability loss and bounded cleanup.

Focused group: 73 tests, zero failures, seed 0 (new ingress, existing STT
ingress, STS/general descriptor contracts, Google codec/session). The Google
subset has 24 tests, including no history/audio replay on a resumed socket.
Rechecked the official Google session-management guide in response to the
user's concern: a handle resumes server-side state, not an audio replay
command. Hosted continuity remains unverified and unadvertised; no billable
calls were made.

The primitive intentionally is not yet wired into production. Next work must
bind it to the exact authorized caller/allocation, register a policy enforcer
group, recheck policy/hold at the capability, and prepare independent transport
conversion/readiness. Real-room Morse audio, publication/playback settlement,
three-mode calls and bounded ten-call load remain missing. Preserve the
milestone's unchecked acceptance items.

## Root verification exposed STT startup race

The first full-root run failed the existing `SpeechToTextMediaPolicyRoomTest`
case "planned room binds STT to its current media policy before accepting
audio" (line 1045): a synthetic Deepgram transport started under a policy with
no transcript consumer. Isolated and 25-test file reruns passed, consistent
with an ordering race rather than proof that the failure was harmless.

Inspection found `RoomSupervisor.start_connection_speech_to_text/4` omitted
`initial_policy`, so the controller's default demand started an allocation
before enforcer registration installed the actual denial. A fast provider
could connect before that allocation was retired. Reused the existing red
room regression and changed the attachment path to fetch/validate the exact
incarnation's policy (bounded 1-second query) and pass `initial_policy` before
allocation. Missing/dead policy authority fails attachment; registration still
revalidates the current policy before live audio opens. No timeout was enlarged.

The room-policy/controller/STS-room/ingress regression group passed 52 tests
with both seeds 0 and 92641. The main 73-test input/Google group also passed
seed 92641. A compile
warning from a temporarily split function-clause group was fixed by grouping
the clauses again. Final root verification remains pending after this repair;
retain the first failing run as evidence, not a successful acceptance run.

## Next integration checks (inspection only)

- `ConnectionAttachment.media_ingress`, WebRTC `SpeechInput.prepare/3`, and
  telephony `IncomingAudio.deliver/5` still expose only human STT. Keep their
  existing semantics while adding the separate STS handle/conversion state.
  Existing converters support the relevant mono 16 kHz PCM targets; no new
  codec dependency is needed for the current Morse/Google profiles.
- `Media.ConnectionReadiness` has a closed demand vocabulary containing only
  `audio_input?`, `room_output?`, `speech_to_text?`. STS requires its own demand
  and resource checks, including when human STT is absent.
- `Startup.install/2` installs the STS runtime but does not revisit connections
  attached before asynchronous preparation. A static handle obtained only at
  attachment will miss this case; test readiness-time binding explicitly.
- `SpeechToSpeech.maybe_start/2` currently accepts any connection with a sink,
  while assigning the entry caller's identity. Require the authorized entry
  caller before enabling microphone input; test monitor/noncaller-first and
  duplicate early attachments. Candidate input and output must stay closed.
- Use existing `Authority.register_connection_enforcers/4` for the capability
  and ingress together. Group semantics retire siblings on allocation failure;
  independent enforcer registrations cannot provide that contract.
- Controller creation must not query its parent supervisor during that parent's
  `init/1`. Use the existing tree-local registered-name/start-wrapper pattern,
  then resolve child handles after tree startup. Test the real room round trip
  before broadening to transport and all three transcript modes.

## Commit preparation

The user requested committing the accumulated STS work on `sts-impl`, with
motivation and verification in the commit description. Inspected the staged
implementation/tests/docs and excluded the separate runner-default edit from
this checkpoint. The user then explicitly approved a separate runner commit;
its shell syntax and fake-executable fixture checks passed. Removed an empty
untracked review-note placeholder; it contained no findings.

Clarified that fresh-session history reconstruction is not a prerequisite for
handle resumption or this milestone. There is no implemented replay fallback.
The setup-catalog fixture passes all 3 tests and `npm run check` passes; only
test text changed in frontend source, not the rendered interface. No push to
the remote, hosted calls or delegation occurred.

Ran the native Morse STS example with input `HI`: it emitted caller text `HI`,
agent text `RECEIVED HI`, and 182,400 PCM bytes. Independently read the WAV
header (16 kHz, mono, 16-bit PCM) and fed the generated PCM through the Morse
decoder; its final text was exactly `RECEIVED HI`. The system `file` command
was unavailable, so a Node built-in binary reader checked the header instead.
The WAV is a temporary verification artifact, not a committed recording. This
is provider/example evidence, not a room microphone round trip.

## Final verification

All root gates passed after the STT admission repair:
`mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `PGHOST=/var/run/postgresql mix test --seed 0`, and
`mix deps.unlock --check-unused`. The final umbrella run contains **2,166 tests,
zero failures, 42 excluded**: Call Engine 1,019; Gateway 480; Console 191;
Persistence 185; Calls 120; Agent Runtime 95; MCP 37; Artifacts 20; Providers 19.
The earlier full run had exactly the STT policy-startup failure described above;
all its other application suites passed. `git diff --cached --check` is clean.

Checkpoint ready to commit, not milestone completion: source binding,
independent transport fanout, real-room microphone/transcript/playback proof,
remaining lifecycle/tool work and final acceptance gates are still open.
