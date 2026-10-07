# Gemini opening transcript

## Approved contract and design review

2026-10-07: Read the full opening-transcript brief, root instructions, Gemini
milestone and protected-opening contract. The worktree starts at b5500c30 with
only an unrelated Wrangler labnote untracked; preserve it. The user subsequently
authorized a coherent commit after verification.

Production must release bounded completed fixed-opening audio when Gemini sends
no output transcription. Do not synthesize the author's expected text and do not
add a recognition model to production. Present but incorrect or incomplete text,
interruption, empty audio and overflow must continue failing. Wait through turn
completion so a late valid transcript remains usable. Protection must still last
until physical playback finishes, even without text.

Design review: the Google adapter owns bounded opening assembly and validation;
the STS capability owns physical playback settlement. Verify both boundaries with
ordinary tests. The tagged hosted test collects actual output PCM and uses the
existing Deepgram recognition boundary only when Gemini text is absent. Reject
expected-text substitution, runtime STT fallback and raised timeout bounds.

## Verification

Initial gate plan: provider red/green, capability completion without synthetic
text, live Gemini repetitions and relevant carrier checks, all root gates and
Lean. Checkpoint results below record actual progress.

## Red/green evidence

- Provider red: both response-start profiles close with `:session_failed` instead
  of delivering the captured PCM (2/2 failures, seed 694858). At completed turns,
  release audio and replay the actual model boundary only when generation ended,
  audio exists and no transcript was supplied. Present incomplete/wrong/extra
  words remain rejected. Existing overflow/interruption bounds remain unchanged.
- Provider suite is green: 56 tests, zero failures, seed 273971.
- Capability red: after the adapter fix, both profiles still fail with
  `:output_transcript_missing` before physical playback (2/2, seed 648303).
  Permit text-free settlement only for the current fixed Google opening. Freeze
  the absence of text at generation completion, publish no transcript, retain
  physical playback as the protection fence and admit subsequent ordinary speech.
  Focused capability red becomes green (2/0, seed 721614).
- Broader Google session/controller/common STS/duplex group passes 215 tests,
  zero failures, seed 901465. Additional absent/unfinished PCM guards now check
  that turn completion alone cannot authorize audio release.
- Hosted tests collect original credited 24 kHz PCM per turn. A missing output
  transcript is confirmed through the existing Deepgram STT session, converted
  to its 16 kHz input and paced with silence for normal semantic completion.
  Recognition remains test-only and inside the existing hosted deadline. A
  separate generated live case forces independent opening-audio confirmation
  even when Gemini supplies its transcript. Initial live run: 3/0 in 12.9 s,
  seed 74780, including real Deepgram recognition. No timeout was increased.

- The first repeated series passed three runs and recognized a naturally omitted
  opening transcript. Run four recognized another omission but failed the forced
  independent check because streaming Deepgram never finalized one short clip
  within the existing deadline (seed 35950). Replace test-only conversational
  endpointing with finite Deepgram recognition of the original captured PCM;
  do not increase silence, wait bounds or retry. The finite endpoint declares
  the real 24 kHz mono linear16 format and receives no expected-word hints.
  Primary API reference: https://developers.deepgram.com/docs/pre-recorded-audio
  and https://developers.deepgram.com/docs/sample-rate/.
- Finite-recognition helper tests first fail because the boundary does not exist
  (5/5, seed 170804). They cover raw PCM/format, no wording hints, empty or malformed
  recognition and HTTP rejection using a local Req stub, without live accounts.
- Finite boundary is green (5/0, seed 198616); its first hosted run passes 3/0
  in 11.5 s (seed 824993). It submits the original PCM directly, with no resampling,
  silence extension or retry. Request waits are capped at ten seconds and the
  remaining original hosted deadline.
- The new negative-audio fixture initially omitted input-event acknowledgement
  and attempted a synchronous state read after expected termination. Corrected
  the harness rather than runtime behavior. Expanded speech group passes 217/0
  (seed 304903). Strict Credo, formatting, warnings-as-errors compilation,
  unused-dependency check and Lean build/oracle/replay pass; Lean replay seed
  300740. Full umbrella and fresh thirty-run hosted series are in progress.

## Repeated hosted acceptance

The fresh finite-recognition series passes all thirty consecutive full Gemini
hosted selections: 90 tests, zero failures. Seven fixed openings naturally omit
the provider transcript. Each is confirmed as Alpha by Deepgram from the original
PCM and proceeds through its subsequent typed turn. Every selection additionally
exercises independent waveform recognition with provider transcription ignored
only by the test assertion. The final series does not retry or raise any wait.
The initial unsuccessful streaming attempt is retained above as separate evidence.

## Full verification

- The final root suite passes all nine apps: 3,266 tests, zero failures,
  114 excluded, seed 576967. Call Engine passes 1,942 and Gateway 571.
- Formatting, warnings-as-errors compilation, strict Credo and unused-dependency
  checks pass. Lean builds its four jobs, reports no oracle drift and passes
  its replay (seed 300740). No UI source or dependency changes were needed.
- Thirty consecutive full hosted Gemini selections pass 90/0, including seven
  natural fixed-opening transcript omissions confirmed from their actual PCM.
- Gemini carrier round-trip/barge-in finished 2/2 failing in 75.9 s (seed 502758).
  All three Funnel relays were healthy before each dial. The opening/count was
  not heard remotely; both rooms stayed running with no Google failure recorded.
  Mixer buffers remained at 32 timestamps with 1,110–1,869 overflow counts. These
  observations do not establish the cause. Additional phone acceptance remains
  unchecked; do not substitute a rerun or a longer wait for a repair.
- Optional Twilio discovery reported its inactive account and continued through
  the Telnyx pair. Test-owned public tools stopped afterwards; tools:status reports
  the node stopped. The pre-existing system Tailscale daemon was left alone.
- Documentation relative links and the unchanged 41/31 milestone counts resolve
  correctly. Broader Gemini and parent STS acceptance remain unchecked.

## Commit handoff

The user authorized committing the verified checkpoint. After the environment
changed, exact-path staging failed because Git metadata is mounted read-only
(`index.lock`: Read-only file system). No paths were staged or committed. Source,
tests and documentation remain intact; the unrelated Wrangler labnote is excluded.
Restore writable Git metadata before staging and reviewing the checkpoint for its
authorized commit. Phone acceptance remains a separately recorded failure.
