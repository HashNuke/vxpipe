# Protect phone openings

## Scope and decisions

Continue the inherited uncommitted GPT-Live phone input, fixture and runner work.
User decision: fixed and generated openings play fully. Text agents collect caller
turns but dispatch them only after opening playback completes. STS drops caller
PCM and external activity throughout its opening. Generation completion is not
playback completion. Policy revocation, transfer and teardown retain their fences.

Normalize STS sink PCM to 48 kHz in Call Engine; provider credit, recognition and
usage retain their original PCM rate and payload. Move the inherited timestamp
anchored mono linear16 resampler into Call Engine so Gateway can reuse it without
reversing application dependencies. Keep an absolute source sample count per
output turn for chunk tiling. Interpolation holds the last sample within each chunk.

## Red-green evidence

- Four new fixed/generated overlap tests initially failed: GPT-Live received
  caller input and text opening playback was interrupted. After opening gates and
  a bounded (16 turn) text queue, all four passed.
- Three boundary tests initially failed: GPT-Live output was 24 kHz, external
  STS activity reached the provider, and the room never completed its STS opening.
- First relevant group: 172 tests, three failures. One hand-built state lacked
  opening fields; two existing assertions compared sink bytes to source-rate bytes.
  Adapted assertions to preserve acoustic sample and source-usage checks at the
  new sink rate, and opening helpers tolerate states with no opening lifecycle.

## Pending verification

Focused suites, framed ingress regression, selected live carrier rerun, scaffold
removal, shell runner tests, root gates and Lean verification remain to run.
The parent GPT-Live milestone remains incomplete while its hosted gates are open.
No provider environment file has been read or edited; use the authorized runner.

## First continuation live run

All three public relays were healthy. The call remained answered and both rooms
remained running, but GPT-Live produced no opening: removing all input also removed
its continuous input clock. Official OpenAI greeting guidance explicitly requires
input audio to keep running, including silence. This replaces the initial blanket
PCM drop with same-duration synthetic silence for `output_shape: :continuous`.
Caller audio is still discarded; turn-based STS receives no PCM. Four direct/framed
fixed/generated clock regressions failed before this adjustment (no input append).

## Clock and carrier checkpoint

The clock adjustment passed 78 focused capability tests, including fixed/generated
openings over direct/framed input. The live Twilio → Telnyx case passed in 24.1 s:
Alpha reached the receiving phone, Bravo reached the GPT-Live room, Charlie reached
the phone, both rooms terminated and durable outgoing outcome was answered. All
three public relays returned 200 before dialing. Removed the temporary receiver
silence switch, provider process tracing and invasive readiness diagnostics.
Existing bounded carrier/media diagnostics remain for assertion failures.

Gateway input: 8/0; Console fixture: 3/0; all three livetests shell suites passed.
Strict Credo and warnings-as-errors compile passed before fixture cleanup.
A clean carrier rerun, direct hosted continuation check, final root gates and Lean
remain. The wider GPT-Live milestone stays incomplete for its remaining checkpoint F
phone scenarios. Keeping a tools:up command alone alive is ineffective under this
execution environment: background descendants are cleaned when its command exits.

## Direct hosted harness

The two existing direct hosted checks ran: delegated tool continuation passed,
but the talk-over scenario timed out awaiting its next response (117.2 s total).
The harness sends a fixture plus two seconds of silence in an immediate batch,
then stops input while awaiting provider events. It therefore has the same missing
clock issue as the first protected-opening live run. Keep sending 20 ms synthetic
silence when its event wait is idle, with the provider's most recent accepted origin;
preserve all assertions and the original 110 s deadline. This is a harness change,
not a provider override or relaxation of the accepted protocol.

Direct hosted clock rerun: both existing tests pass (17.4 s). Tool continuation,
short response, talk-over yield, mute hold and forced history reseed all retain
their assertions. This direct-session evidence does not substitute for those
scenarios over an actual phone leg.

Clean carrier rerun after scaffold removal: 1/0, 22.3 s, all three relay health
checks returned 200. Receiver still opens first with Bravo. Alpha/Bravo/Charlie,
both process terminations, durable closure and answered outcome passed unchanged.

## First root gate pass

Format, warnings-as-errors compile and strict Credo passed. The default umbrella
run exposed nine Google controller checks whose shared sink assertion still expected
24 kHz bytes; update it to check 48 kHz, doubled constant samples and unchanged 20 ms
duration. The same run reported an unrelated MCP wire-security test receiving an
unexpected GET stream despite its mixed-DNS POST being rejected. Stop this known-red
umbrella run and reproduce the MCP case in its owning suite before a final full run.

The Engine group finished before the stop, revealing 79 failures: the shared
Google assertion affected 50 controller cases, and room Morse decoders/duration
helpers accounted for the remainder. Update sink decoders to 48 kHz and calculate
playback from sink samples; keep microphone fixtures and recognition at native
rates. Preserve every decoded phrase, interruption and history assertion.
The MCP owning suite at the same seed passed 37/0; no MCP code or test was changed.

The affected Google, room STS, outgoing opening and expanded text/speech opening
suites pass together: 191 tests, zero failures (75.4 s). No decoded phrase or
terminal assertion was removed. A new full umbrella gate run is now underway.

## Final completion checks and checkpoint review

All six root gates pass: `mix format --check-formatted`, `mix compile
--warnings-as-errors`, `mix credo --strict`, `mix test`, `mix deps.unlock
--check-unused`, and `bin/verify-lean`. The default umbrella completed 3,220 tests,
zero failures, 105 exclusions, seed 113691. Counts by application: MCP 37,
Providers 29, Agent Runtime 99, Call Engine 1,900, Calls 134, Gateway 571,
Artifacts 20, Persistence 214, Console 216. Gateway's native lane took 468.3 s;
Call Engine took 196.3 s. The Lean model build, oracle drift check and Elixir replay
pass (one replay test). The prior MCP one-off did not recur in this full pass.

The selected clean real carrier check is 1/0 (22.3 s); direct hosted GPT-Live is
2/0 (17.4 s); all three runner shell suites pass. Exact checkpoint paths and staged
changes were reviewed, local documentation link targets exist, and checks found
no credential-shaped literals or local home absolute paths in added content.
The unrelated Wrangler cache-repair labnote remains untracked and unchanged.
The test Funnel node started for this task has been stopped.

The requested continuation (protected openings, phone-rate normalization, successful
receiver-first carrier rerun and removal of scaffolding) is complete. Checkpoint F's
remaining advanced carrier scenarios retain their unchecked status; direct-session
tool/hold/reseed checks are not reported as carrier acceptance. The separate local
design review is recorded with the milestone amendment and decision document.
