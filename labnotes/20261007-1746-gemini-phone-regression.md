# Gemini phone regression

## Scope and initial evidence

2026-10-07: Start at c7b232b8 with only the unrelated Wrangler labnote untracked.
The user requests actual diagnosis of the two Gemini Telnyx phone failures,
comparison with b5500c30, an owning non-live red before the fix, repeated Gemini
phone proof, GPT-Live phone regression, hosted Gemini and all root/Lean gates.
Do not add or increase waits/timeouts; publish readiness evidence if setup races.
The user authorizes committing after verification. Git refresh succeeds: metadata
is writable again. Never read or modify the private provider env file.

The first exact reproduction is running through bin/livetests. The previous
502758 failure had live rooms, completed agent output, healthy public relays,
no Google failures and high mixer overflow counts. These are observations, not
an established cause. c7b232b8 changes fixed Google transcript-free opening
settlement; it does not alter native transport or mixer configuration.

Room completion inspection: the STS turn-completed handler marks FirstMessage
completed independently of an agent transcript. The capability's audio-only
opening branch keeps physical playback as its completion fence. Verify these
boundaries with real room evidence rather than assuming they caused the fault.

## First reproduction

Exact current-HEAD command reproduces the silent barge-in case: 2 tests, 1 failure,
seed 456656. Round-trip succeeds; barge-in has a
completed opening but the peer hears nothing, both calls remain running, no Google
failure, and 1,760–1,861 mixer overflows. All three relays were healthy. Preparing
a temporary detached b5500c30 checkout with separate copied test build artifacts
and shared dependency sources; do not change the main checkout to compare it.

## Funnel recovery and timestamp diagnosis

The first detached-baseline selection (seed 102898) and next current selection
(seed 218111) each fail both cases before any dial: advertised public relay TLS
handshakes time out. Private MagicDNS health is 200 but bypasses public ingress.
The tagged test node has Funnel/HTTPS capabilities, no current health warnings,
and Tailnet Lock is disabled. Refreshing only the test daemon, its Funnel mapping
and its node advertisement restores every public relay within the existing
300-second startup bound. Temporary DERP preference experiments are reverted;
there is no timeout change or weakened relay guard. Keep the initiating command
alive during the comparison so this execution environment does not reap the
background test daemon. The unrelated system Tailscale daemon remains untouched.
The user explicitly brings Funnel repair into scope. Public ingress now remains
healthy before subsequent dials; the upstream reason for slow relay recovery is
not established.

Current phone selection seed 839293 repeats round-trip pass/barge-in silence.
Numeric mixer diagnostics show approximately 40 seconds elapsed while retained
input timestamps represent hundreds of seconds. Playout ticks continue. The
baseline selection also captures future input timestamps, so this fault predates
c7b232b8. Its round-trip separately encounters the earlier fixed-opening
`:text_mismatch` failure; its barge-in passes (2 tests, 1 failure).

A bounded numeric ingress probe captures the pinned Telnyx Opus timestamp
advancing 320 per approximately 20 milliseconds: a 16 kHz sample clock. PacketSource
incorrectly treats that timestamp as milliseconds. A focused Gateway red submits
two consecutive real Opus packets with sample timestamps 320/640. The first room
frame is 1920; the second is incorrectly 17280 instead of 2880. Changing only the
packet source to sample-clock-to-Membrane-time conversion makes all four owning
pipeline tests pass. Synthetic phone-handoff tones now emit Telnyx sample-clock
timestamps; the 15-test Telnyx harness passes again.

The first shared live STS selection after this fix (seed 245191) has 4 tests,
1 failure: both round-trips and GPT-Live barge-in pass; Gemini barge-in still
misses its opening. Both mixers now have zero overflows and ordinary current
buffer timestamps. Thus the clock bug is a confirmed repair, not the entire
cause of the silent STS exchange. Temporary provider-ready timing probes are
being used to establish whether the receiving model is ready before the opening.

## Startup race and handshake repair

Five isolated Gemini barge-in selections pass. Repeating the paired selection
with seed 839293 still fails barge-in after the round-trip passes. Its receiving
GPT capability announces ready at 18:24:38.497, while Gemini's opening completes
at 18:24:38.760. Only 263 ms of the opening interval remains; the peer publishes
no Alpha. Startup input is deliberately closed (covered by STSIngress's existing
closed-input tests). This timing and the live silence identify the fixture's
short opening trigger as a race with the receiver startup, rather than a stuck
Gemini playback/completion loop. The production opening still plays and completes.

A Console focused red requires the counter to wait for input and the receiver to
open with Ready for either provider; the old Alpha/receiver-waits pairing fails
that contract (8 tests, 1 failure, seed 470521). The fixture now sends its existing
Ready signal as a protected fixed opening after receiver startup. Both providers
count only after hearing it over the carrier. The round-trip continues requiring
fixed Alpha/Bravo/Charlie, and the long scenario keeps its separate Ping/Pong
contract. The focused suite is green: 8 tests, zero failures, seed 770862. All
temporary private-state/numeric-readiness probes are removed from the main tree.

First shared acceptance after the handshake repair (seed 372030): both Gemini
cases and GPT round-trip pass. GPT barge-in counts, records overlap, and receives
Stop counting, but its peer does not record the required stopped reply; one
unknown-category STS provider failure is observed. This is not counted as a
fully green selection. The next GPT-only selection passes both cases, seed
690869, 40.7 seconds. Direct hosted Gemini passes all 3 tests, seed 854174,
including independent Deepgram output confirmation and a subsequent turn.

Formatting, warnings-as-errors compilation, strict Credo and unused-dependency
checks pass. Lean build/oracle/replay passes. An overlapping root test/Mix run
fails during protocol consolidation with missing generated beam files: this is
an execution mistake from concurrent writers to the shared test build. Re-run
the full suite serially after live selections; do not count that attempt as a
project verification result. Repeated paired Gemini acceptance is running with
the previously failing seed 839293.

## Further acceptance failures and probes

The first repeated pair passes, but the second pair hears Ready and starts an
agent output without remotely recognized counting; no provider error is recorded
and mixer overflow remains zero. Stop that loop: the repair is not yet verified.
Further bounded snapshots distinguish this from the original missing Alpha.
One next pair ends both rooms after an incoming GPT capability failure, with safe
categories unavailable/unknown. Another pair fails only the short Alpha assertion:
it hears four Bravos and completes four agent turns; the barge-in case passes.
These results remain failures in the evidence. The original opening audio path
is demonstrably able to release, settle and continue, but short carrier
acceptance still requires repeated verification. Temporary probes include only
flags and counters from the owning Call Engine application; no text, PCM or
credentials are dumped.

The next three consecutive paired selections (probe runs 4–6, seed 839293)
pass all six tests. Continue a bounded sequence to establish repeated clean
acceptance. The diagnostic helper initially had a comma syntax error, corrected
before the next selection; that compile-only failure submits no carrier dial.

## Pending-opening input window

Probe run 7 fails the round-trip explicitly at fixed-opening `:text_mismatch`;
its barge-in passes. The earlier snapshot-only failure had no such provider
failure, so preserve the distinction. Inspecting room startup finds a concrete
regulatory-opening gap: caller input is released before FirstMessage sends the
opening command, while capability protection initially defaults false. A
callee's already-playing Bravo can reach the model in that window and contaminate
its opening response. The previous fixed-only prompt also incorrectly told the
model it had already said Alpha while permitting only Charlie responses; make
that fixture prompt describe the required future opening instead.

The focused owning capability red constructs a pending opening and sends EARLY
PCM before begin_opening. It incorrectly emits caller speech evidence: 1 test,
1 failure, seed 567963. Initialize protection from the room-owned pending
FirstMessage at capability allocation; keep wait_for_input unprotected. The same
red is green (seed 418985), and the capability/duplex/room group passes 122 tests,
zero failures. Protection still ends through existing physical output settlement;
continuous providers retain silence and turn-based providers drop PCM. No timer
or source authorization changes. Re-run carrier acceptance for this runtime
repair rather than counting prior passes as its evidence.

The first carrier pair after pending-input protection passes barge-in but fails
round-trip after Alpha and Bravo are heard. Google completes and physically settles
both outputs; its active output and response records are empty. The receiving
Deepgram TTS allocation closes with `:session_failed` during its text-agent reply,
then the phone connection detaches. Preserve this separate failure rather than
attributing it to the Google audio-only path. Add temporary bounded stage probes
to the Deepgram session for decode, publication, audio rejection and disconnect;
these log only atoms, phase and flags, never provider payloads.

All three public Funnel relays independently return HTTP 200 during the next
carrier selection. The dedicated test node reports Running, online and no health
warnings. Recovery is operational; the underlying earlier upstream TLS stall has
not been established. No relay timeout or carrier assertion bound changes.

The next paired run passes round-trip but its incoming GPT fixed Ready allocation
fails before any recognized input or output. The following diagnostic invocation
hits a temporary probe syntax error before dialing; correct interpolation and
retain that attempt as compile-only evidence. The next real pair passes both
cases, seed 681836, 39.0 seconds. Further sequential pairs use the previously
failing seed. Runner shell suites pass: general loading/selection, telephony
provisioning and tools lifecycle/all-relay readiness.

Four consecutive paired Gemini selections now pass after the pending-opening
repair: eight tests, zero failures. The first uses seed 681836 (39.0 s); the next
three use the previously failing seed 839293 (36.4, 37.3 and 36.8 s). Each selection
requires remote Alpha/Bravo/Charlie, physical cleanup of both round-trip rooms,
actual overlapping count/interruption and the spoken stopped response. All relays
are healthy before every submission. No later Deepgram/GPT probe failure is
observed in these selections; their earlier unexplained allocation closures remain
recorded above. Remove every temporary native/session snapshot and IO probe before
the final shared carrier selection and root gates.

The probe-free shared selection (seed 875028) passes both Gemini cases but fails
both GPT cases. GPT round-trip fails before an incoming room appears; GPT barge-in
hears Ready and remotely delivers one/two, then an unknown-category STS failure
ends both calls before the stopped reply. All relay checks remain HTTP 200. This
selection is not green; retain it as evidence. A bounded GPT-only diagnostic run
captures the capability's atom failure reason and native output failure reason,
using the earlier passing GPT seed, before deciding whether this is a regression
of the shared fixture or an independent provider lifecycle fault.

The bounded GPT-only diagnostic selection passes both cases, seed 690869, 42.3 s;
no capability/native failure probe fires. It does not establish the earlier
unknown failure's cause. Remove those two temporary probes again and run the
shared four-case selection once more with that seed. Do not hide the preceding
failed selection or claim that every historical provider closure was repaired.

The next probe-free shared selection fails 3/4 (seed 690869): Gemini barge-in
loses its incoming GPT capability after Ready; Gemini round-trip hears the required
speech but does not naturally retire its receiving room after hangup; GPT barge-in
loses the incoming capability before Ready. GPT round-trip passes. The next
single Gemini barge-in also fails. A producer-DOWN atom probe does not fire,
suggesting allocation retirement precedes native-process termination. Instrument
the shared input/channel failure boundary with only operation-presence flags,
result atoms, exception-module names and timeout/noproc categories. Acceptance
remains incomplete despite the earlier four consecutive paired passes.

The shared input/channel diagnostic pair passes 2/0 (seed 690869, 37.0 s) without
any failure probe firing. The first native-DOWN probe alone did not capture the
preceding failure. Add a temporary wrapper around GPT callback results to log only
stop-stage atom, shutdown atom, fixed-opening-presence and ready flags; retain
redacted payloads. This is diagnostic scaffolding, not a runtime repair, and must
be removed before verification/commit.

The callback-result trace captures the receiver's native failure:
`{:output_fragment, :session_failed, true, true}` (fixed-opening-present and
ready flags). The
shared selection passes both Gemini cases but GPT round-trip separately has a
receiving room with no attached media and GPT barge-in fails this fixed Ready
verification (4 tests, 2 failures). The counter has wait_for_input, so the fixed
opening belongs to its receiving GPT prelude. Barge-in needs an audible Ready
signal, not this additional strict fixed-opening contract. Keep fixed opening
proof in round-trip and use a generated receiver opening instructed to say Ready;
the live assertion still requires remotely heard Ready before counting.

The owning Console fixture red expects generated Ready and an explicit opening
instruction for both tested providers; it fails on the fixed Ready spec (1/1,
seed 697351). Change only the receiver opening mode and prompt, retaining the
counter, overlap and stopped assertions. All temporary callback, channel/input
and producer-DOWN probes are removed before subsequent verification.

Generated Ready fixture green: 8 tests, zero failures. Its first shared live
selection fails all four cases at public readiness before any dial (seed 690869).
The online, healthy dedicated Funnel node intermittently resets public TLS;
independent curl also reproduces a relay TLS failure, while the other relays serve
200. UDP/IPv4/IPv6 netcheck is healthy with stable NAT mapping. A re-STUN connection
refresh precedes all three relays serving 502 without a listener, followed by all
three serving 200 during the next selection. This recurrence means the earlier
restart is operational recovery, not a permanent fix. Tailscale 1.102.2 already
contains the [official Funnel ingress fix](https://tailscale.com/changelog#2026-08-04); no evidence warrants attributing
this failure to that resolved regression or changing the machine's system daemon.
No provider env file is read directly and no timeout/relay guard is weakened.

The probe-free shared selection with generated Ready passes all four cases,
seed 690869: both provider round-trips and both barge-in checks. Its every-relay
preflight is HTTP 200 for all four submissions. Continue with the two original
failing Gemini seeds, hosted Gemini and serialized root gates before committing.

Final probe-free live evidence after generated Ready and public recovery:
shared Google/OpenAI selection 4/0 (seed 690869); Gemini pairs 2/0 with original
seed 502758 (37.9 s) and 2/0 with seed 839293 (35.7 s); direct hosted Gemini 3/0
(11.5 s), including independent test-only Deepgram output recognition. This gives
three consecutive passing Gemini pairs across the final shared and Gemini-only
selections, plus both GPT phone cases. All advertised relays are healthy before
these dials. Begin the five root gates and Lean serially; keep earlier failed
carrier and pre-dial selections in the record. Long-call acceptance remains open.

Formatting, warnings-as-errors compilation and strict Credo pass. The serialized
full default run reveals an existing Morse FIFO assertion mismatch: the public
Session request returns `{:error, :session_failed}`, while the test expects a
private `:pending_reply_overflow` or already-closed channel. The shared Input
boundary intentionally normalizes fatal provider replies to session_failed; the
provider monitor still proves the exact `{:shutdown, :pending_reply_overflow}`.
Correct the public-result assertion to the two semantic outcomes, retaining the
exact monitored overflow requirement. No runtime handling or timeout changes.
Run the focused owning suite and repeat the root gates after the current run ends.

The same default run's second failure is the room-monitor test: it receives
`:noproc` instead of the controlled startup-timeout shutdown. Add a room
acknowledgement after obtaining the monitor and before firing the fixture's
manual timer, so the target has processed the earlier monitor signal. This uses
the existing sys acknowledgement convention, not a sleep or larger bound. The
identity mismatch and exact startup-timeout assertions remain required. Verify
the affected owning suites after the full run exits, then rerun all gates.

After final live selections, remove the owned detached baseline checkout and
stop only the dedicated public test node/keepalive process. Its persisted node
identity remains available for later runs. The unrelated system daemon and
Wrangler labnote are preserved. The serialized default suite continues through
Gateway media cases; do not overlap another Mix writer with that run.

The first full run completes 3,269 tests with exactly those two Call Engine
failures (seed 44264); Gateway passes 572/0 and every other application passes.
The affected two owning suites now pass 29/0 using the same seed. Check the two
corrected cases repeatedly, then rerun the full root gates serially. Do not count
the previous failing full run as acceptance, even though its live-independent
failure checks have been corrected.

The two corrected cases pass the initial run plus 25 repeats (52 executions,
zero failures), seed 44264. Start a fresh serialized format/compile/Credo/default
suite/unused-dependency/Lean pass with that seed. Source and live fixtures are
unchanged since the final passing carrier/hosted selections; only these local
assertion and acknowledgement corrections were added.

The fresh full run passes both earlier corrected cases but exposes another
fixture race: hybrid permitted-STT submission returns stale_frame. Its helper
retries 100 times against a wall-clock source cutoff; all attempts can occur in
the same cutoff millisecond and correctly be rejected. The test concerns permitted
transcription after STS audio denial, not wall-clock pacing. Use Media.Ingress's
existing clock injection only for the two external/hybrid cases and advance that
fixture clock for each submitted frame, matching received_at to it. Preserve
production cutoff/age checks, generation replacement, no STS allocation and the
required caller transcript. No sleep, deadline or retry-count increase.

The permitted-transcription pair passes 26 focused iterations (52 executions,
zero failures), seed 44264, with the manual ingress clock. Correct a log-summary
mistake: the second full run also has one Gateway handoff failure (singular
failure was missed by the initial plural-only filter). The five-participant wait
cursor case recovers with media_unavailable before its native adoption gate is
reached; inspect that existing setup race before the next full run. Do not count
this default run as green or alter deadlines to mask it.

The default Gateway failure is the existing five-participant changing-listener
handoff regression already recorded as intermittent in the parent milestone.
The captured recovery is media_unavailable at about 9.6 s, before the adoption
hook; the phone changes do not alter that WebRTC-only path. Run its focused owning
case to separate an existing intermittence from these repairs. Do not claim a
cause or change its wait limits from this single observation.

The isolated owning Gateway handoff case passes with seed 44264. This does not
establish a cause or a repair of the previously recorded intermittent WebRTC
failure; retain that parent milestone limitation. No handoff production code,
fixture, timeout or acceptance assertion is changed. The final full rerun must
pass this case too before the checkpoint is committed.

The next full run passes all 1,943 Call Engine tests but misses the terminal wire
progress in Gateway's existing release-deadline human handoff case. Its captured
room shutdown has the expected handoff_release_failed reason; the isolated owning
case then passes (one test, zero failures, seed 44264). Neither isolated pass
establishes a repair of these intermittent WebRTC cases. Leave their runtime and
assertions intact, retain the failure evidence and rerun the complete default
suite. Lean build/oracle/replay and unused-dependency checks pass separately.

A fourth full run exposes a different existing native repeated-AI handoff
failure: the receiving model never begins preparation because the room's policy
authority aborts after a room-audio egress process shuts down. The wire reports
policy_changed after 3 ms, not a slow model startup. A temporary atom-only egress
failure diagnostic is added to identify that boundary's cause; it must be removed
before commit. The isolated repeated-AI case passes (one test, zero failures,
seed 44264), so run the owning handoff suite with the diagnostic rather than
continuing uninstrumented full retries. No timeout or assertion is relaxed.

The owning WebRTC handoff suite passes all 67 default cases (one integration case
excluded), seed 44264. Its temporary egress diagnostic does not reproduce a
failing case; two unavailable categories appear during shutdown without an
assertion failure. Remove that diagnostic completely. No evidence warrants
changing the policy boundary or claiming these prior intermittent failures are
fixed. Run the complete default suite again from the clean final source, retaining
these failures and owning-suite evidence in the record.

## Final checkpoint verification

The clean final umbrella default run passes all nine applications: 3,269 tests,
zero failures, 114 exclusions, seed 44264. Call Engine is 1,943/0 and Gateway is
572/0. Final serialized formatting, warnings-as-errors compilation, strict Credo,
unused-dependency checks and Lean build/oracle/replay all pass after removing the
temporary diagnostic. Review and stage only this checkpoint's exact paths; retain
the unrelated Wrangler labnote. No timeouts, waits or mixer limits were increased.

Final live evidence remains three consecutive passing Gemini phone pairs,
including seeds 502758 and 839293, both GPT-Live phone cases and all three hosted
Gemini cases with independent Deepgram recognition. The only changes after these
live passes are local default-suite assertions, clock/monitor acknowledgements
and documentation. Every public Funnel relay was healthy before the final dials;
the dedicated test node and baseline checkout are cleaned up. Public TLS reset
recurrence and earlier native WebRTC intermittence have no established permanent
repair and remain explicitly recorded. Long-call and broader STS acceptance stay
open. Git metadata is writable; the user-authorized coherent checkpoint can now
be committed with implementation, tests, milestone updates and this labnote.
