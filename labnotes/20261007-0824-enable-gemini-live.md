# Enable Gemini Live

## Scope and decisions

2026-10-07: Read the full Gemini brief, root AGENTS.md, milestone index and related
STS/provider prerequisite contracts. Existing Google STS supports the target model,
16 kHz input, 24 kHz output, protected openings, and room-owned barge-in, but is
absent from the manifest/catalog and configured enablement.

The user explicitly authorizes configured Gemini and short real-provider tests.
A subsequent message authorizes the separately tagged long phone session as well.
The initial instruction was to leave this task uncommitted. After verification,
the user explicitly authorized committing the checkpoint. Never read or modify
the private provider env file.
Use only bin/livetests for hosted credentials. Do not raise timeout bounds to
repair flaky behavior. Preserve unrelated untracked Wrangler labnotes.

Design: reuse the existing Google credential and private STS runtime. Extend the
closed selection and live fixtures, keeping GPT-Live defaults intact. Long tests
must have only live_long and their explicit long-session tag, never provider or
ordinary telephony tags. Test observed interruption according to the selected
provider descriptor rather than treating overlap and room interruption as equal.

## Evidence

Initial gate plan: configured startup and fixture reds, direct hosted audio,
short carrier scenarios, approved long call, root gates, Lean and rendered
catalog review. Checkpoint results and the final evidence below supersede this
initial plan.

## First checkpoint evidence

- Configured startup test first failed at selection. Manifest, closed catalog,
  settings and public options now resolve the existing saved Google key. Focused
  startup and Google/controller suite: 201 tests, zero failures, seed 863211.
- Fixture selector test first failed with missing sts_sources/5; green fixture
  and Console catalog group: 18 tests, zero failures, seed 724142.
- Frontend Google STS advertisement test failed before catalog JSON update; all
  frontend tests pass (33 files, 219 tests). No sample recipe was added.
- Direct live PCM and subsequent text turn pass (6.6 s, seed 400990), then a
  real fixed opening passed too (7.4 s combined, seed 834129). The first direct
  test attempts exposed harness misuse of the Session.push_text signature and
  response context; corrected those without changing runtime budgets.
- Chrome desktop 1440x900 and mobile 390x844 inspection: Google STS badge wraps,
  credential dialog keeps its masked password field, no horizontal overflow.
  Used actual Console components with synthetic directory data and read-only
  fetch. Removed temporary preview sources afterwards. Linux Chrome needed
  --no-sandbox; no application permission/configuration change.
- Phone round-trip/barge-in failed with Google session unavailable during the
  opening, despite all three public relays healthy and signed carrier ingress.
  Added bounded provider-failure diagnostics; no timeout increase. Configured
  response-start selection has its own red/green startup regression, but alone
  did not fix the live failure. Capturing bounded wire metadata next; no raw PCM,
  transcripts, keys or handles are printed by the phone trace.
- A location filter selects both generated provider tests at their shared line,
  overriding expected tag selection. Use distinct scenario tags without line
  filters; an incidental GPT round-trip passed during that diagnostic run.

## Caller-onset regression

The focused response-start controller test reproduces real provider caller onset
killing the Google allocation: after typed input and admitted model audio,
ACTIVITY_START caused an unsupported manual interrupt and the provider vanished.
The engine must still fence local playback and publish the interrupted turn.
Allow local discard only after genuine provider-mode caller onset, retaining the
old wire owner until the real server interrupted/model boundary. Independent
manual cancellation continues to fail closed. No fabricated activity/text,
standalone cancel command, history replay or timeout change is introduced.

The diagnostic short phone round-trip then passed once before this fix (seed
810642), 17.5 s, demonstrating the earlier failure
is timing-dependent. Keep that separate from proof of the repair.

## Phone opening root cause

Bounded lifecycle tracing captured response_started, output_transcript and
output_completed, followed by the channel's error reply `:invalid_playback`,
provider kill, channel normal exit and capability `:provider_failed`. Google
wire messages decoded successfully. The original interpretation that Google
closed on a bad wire event was incorrect. Only protocol labels and internal
failure atoms were printed; removed temporary tracing again.

The owning controller regression sends 481 source samples at 24 kHz. Its 48 kHz
sink copy is 1,924 bytes, padded by the native sink into two 20 ms packets.
Physical playback completion is 40 ms but the provider PCM bound is 20 ms.
The initial red failed with `:vxpipe_sts_unavailable, :provider_failed` instead
of the completed transcript, exactly matching the live failure (seed 938033).
The fix retains the physical completion fence and transport duration; it caps
only provider settlement at the duration of accepted original PCM, including
fenced already-generated output. Provider guards/PCM usage remain unchanged.

- Partial final packet regression passed with source-duration settlement; a
  second red proved that an impossible sink report must still fail. Both are
  green (seed 334546). The preceding broader STS group passed 257 tests (seed
  764639); final gates will rerun after all changes.
- Real Gemini phone rerun after the padding fix: round-trip passed, but barge-in
  failed while counting (2 tests, 1 failure, seed 493811). The receiving GPT-Live
  heard Alpha and One; both rooms then ended. Continue tracing channel reasons
  rather than increasing the acceptance timer. Long call remains authorized.

- A selective channel trace corrected the remaining barge-in diagnosis: there
  was no channel rejection after Ready. Google completed a response containing
  only One, and the receiver was waiting for Three before its interruption.
  The room ultimately hit its normal duration limit. Two fixture reds require
  an explicit single-response count; clarified the prompt without loosening
  interruption evidence or increasing waits. Temporary tracing was removed.

- Real barge-in diagnostics confirmed `stage: :audio, reason: :audio_overflow`.
  A focused ordinary session test now preserves that bounded cause rather than
  collapsing it to session_failed; public failure and cleanup stay unchanged.
- Pure response-owner burst red failed at packet seventeen. Compacting only the
  current response's pending PCM preserves byte order, the sixteen-chunk cap,
  131,072-byte chunk cap and fail-closed full-budget overflow. Google adapter
  group passed 67 tests. This does not need a live account to reproduce.
- Shared STS fake-sink backpressure red proved caller input timed out while the
  capability synchronously pushed audio. Isolated sink pushes in the owned tree's
  task supervisor while withholding exact channel credit. An initial one-child
  task-supervisor limit raced with completed-task retirement; protocol-owned
  single credit already bounds active work, so removed that redundant limit.
  Broader Google/common STS/startup group now passes 260 tests.
- Following user guidance, moved the padded-playback tests out of the Google
  controller into the common STS capability suite. Eight ordinary cases cover
  8/16/24/48 kHz: source settlement excludes padding, physical fence retains it,
  impossible duration fails, and next output remains admissible. The blocked-sink
  regression also exercises the shared path. Carrier tests retain only real
  provider/audio/phone acceptance; no timeout was raised.

- Final short Google carrier pair is green: round-trip and genuine barge-in,
  2/0 in 35.1 s (seed 681262). Direct hosted PCM and fixed-opening/subsequent-turn
  checks are green, 2/0 in 8.3 s (seed 95203).
- Approved ten-minute phone lane failed after about 120 s (seed 305445). Ping/Pong was active through the 90 s
  check; the next check found the STS room ended with agent_unavailable. Add
  bounded capability failure diagnostics; do not assume this is the seven-minute
  renewal timer, and do not raise waits. Long acceptance remains incomplete.

- Long diagnostic rerun (seed 576247) captured Google `activity_start` failure
  with `ambiguous_input`: a new caller starts while the earlier ended caller
  lacks its independent final transcript. Existing ordinary controller coverage
  explicitly requires this fail-closed behavior rather than guessing attribution.
  Do not remove that guard to obtain a live pass. The broader qualified caller
  association gate stays open in the parent milestone.
- The long receiver still inherited a fixed Bravo opening from the round-trip
  template. Two fixture reds now require it to wait for Ping before replying
  Pong. This removes unrelated setup speech without changing regulatory-opening
  behavior or increasing waits. Temporary process tracing was removed; bounded
  provider diagnostics remain in both initial-exchange and long-watch failures.

- First full umbrella run: Call Engine had 14 failures; other umbrella suites
  passed. Twelve failures were manual Morse duplex clocks outrunning the newly
  asynchronous sink delivery; two expected Google STS to remain unadvertised.
  Updated the test driver to monitor the owned delivery task and flush capability
  acknowledgement before advancing the manual clock. No sleeps, buffer increase
  or timeout increase. The three affected owning suites now pass 63 tests
  (seed 566185). Input-turn admission tracking moved into its existing Input
  module after strict Credo identified the main capability's size limit; the
  relevant expanded group passes 271 tests (seed 74152).
- Corrected long fixture still fails with `activity_start: ambiguous_input`,
  after 37 s from initial exchange setup (seed 133655). Prior longest attempt
  reached the 120 s check. This is the existing fail-closed caller-association
  boundary, covered by the ordinary Google controller suite, not missing live
  credentials or relay provisioning. The brief requests live checks/results,
  while the parent explicitly leaves qualified caller association open; do not
  silently broaden that contract or mark long acceptance complete.

- Fresh shared real-carrier regression passes all four OpenAI/Google short cases
  (round-trip and barge-in), 4/0 in 81.0 s, seed 990382. This checks the existing
  GPT-Live behavior after the shared output changes.
- Final root static gates pass; the final default Call Engine suite passes
  1,923 tests, zero failures. Remaining umbrella suites and Lean are pending.
- `bin/livetests tools:down` completed and the task's keepalive session ended.
  The pre-existing system Tailscale daemon remains running. All temporary wire,
  channel and process tracing and rendered-preview sources were removed.

## Final verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, and `mix deps.unlock --check-unused` pass.
- `PGHOST=/var/run/postgresql mix test`: 3,246 tests, zero failures, 112 excluded,
  seed 912062. All nine umbrella suites pass, including Call Engine 1,923 and
  Gateway 571. The earlier fourteen failures and their fixture repairs remain
  recorded above rather than being omitted.
- `bin/verify-lean`: four-job build passes, checked-in oracle has no drift,
  conformance replay passes (1/0, seed 128278). This checks the modeled source
  admission slice, not the unimplemented qualified caller-association contract.
- Frontend 219 tests, type check and lint passed; rendered desktop/mobile badge
  and masked credential form reviewed. All three livetests shell suites pass.
- Direct real Google: 2/0, seed 95203. Fresh real carrier short regressions for
  Google and OpenAI: 4/0, seed 990382. Google long lane remains failing at
  ambiguous_input; the new milestone and parent index entries remain unchecked.
- Changed Markdown relative links and index totals (41 specs / 31 complete)
  verified. Exact diffs reviewed, temporary diagnostic/preview files removed,
  live tools stopped. No credentials file was read or modified directly; no
  credential contents, raw PCM or authorization data were added. The user then
  authorized committing this checkpoint with the failing long-call gate recorded;
  the unrelated Wrangler labnote is preserved.
