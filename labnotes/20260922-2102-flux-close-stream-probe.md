# Guarded Flux CloseStream interoperability probe

> Relocated from `docs/flux-close-stream-probe.md` on 2026-10-09. First recorded source commit: `46c158856b23` (2026-09-22T21:02:24+00:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260922-2041-flux-close-probe](20260922-2041-flux-close-probe.md).
> Maintained contracts/progress: [live-provider-tests](../docs/development/live-provider-tests.md), [speech-provider-contract](../docs/speech-provider-contract.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

Decision, 2026-09-22: add test-only evidence collection, not a hosted finite-input
profile. The [protocol research](20260922-2032-deepgram-finite-input-proof.md) and approved
normalized Socket peer-close seam are prerequisites. Production finite admission,
provider selection and hosted milestone acceptance remain unchanged/open.

## Design review before implementation

The [official CloseStream contract](https://developers.deepgram.com/docs/flux/close-stream)
promises decoding received audio and updates before closure, but does not settle
whether our client observes peer close or EOF. One future authorized run can
resolve that interoperability observation for the selected model and fixture;
it cannot establish universal drain correctness or raw empty/1000 distinction.

Use a tagged live-provider test and test-support runner/evidence collector only.
Require explicit Mix selection before reading a fixture, resolving credentials
or connecting. An available credential does not select the test. The hosted
entry point uses `--only live_deepgram` with its exact file path; the default
suite excludes it.

One connection to existing `flux-general-en`, raw signed PCM16LE mono 16 kHz:

1. Validate an operator-supplied regular file: nonempty, even byte count, at most
   320,000 bytes (10 seconds); expected UTF-8 suffix is nonempty, at most 256 bytes.
   No bundled speech, download, transcoding, silence padding or generated TTS.
2. Start an absolute monotonic budget (at most 30 seconds) before connection.
   Require valid Connected before sending PCM in ordered chunks up to 2,560 bytes.
   Then send only the JSON CloseStream control via `Socket.send_frame/2`.
   Do not invoke the production close path, which also closes the client socket.
3. Decode with the existing Flux codec. Retain only latest text per turn, with
   at most 16 turns, 65,536 retained UTF-8 bytes including separators and 256
   forwarded application/terminal events. One extra overflow notification is the
   limit; later callbacks do not forward or decode payloads. The existing codec's
   per-message/text bounds also bound each queued event. Check request identity
   and increasing sequence.
4. Compare the expected exact suffix privately against ordered latest turn text.
   Require successful sends, no decoder/provider errors and an actual normalized
   `:normal_or_no_status` peer-close callback after requesting finish, processed
   strictly before expiry. A shared one-bit finish-request gate stamps the callback
   at observation, so owner mailbox delay cannot promote a pre-finish peer close.
   Successful CloseStream send is independently required. An already-caught-up
   stream need not send another update after CloseStream. A prior EndOfTurn alone
   cannot complete the probe.
5. Return only a terminal class and booleans. Never log/retain transcripts, raw
   responses, close reasons, fixture path, request identity, URL or API key in
   the report. Supervised cleanup is local teardown, never success evidence.

EOF/error/local termination, abnormal/early close, timeout, invalid input,
missing tail or overflow are failed/inconclusive observations. There are no
retries and no timer/quiet-period success path. Offline hooks control connector,
send and monotonic clock to test expiry even when terminal is queued first.
Socket's existing bounded calls and connect/receive timeouts bound blocking work;
any callback returning after expiry cannot authorize success.

Rejected alternatives: credentials as opt-in; production adapter opt-in merely to
probe; ForceEndTurn as flush; requiring a new post-CloseStream update; accepting
EndOfTurn/EOF/local close; raw parser/dependency changes; emitting a transcript
to compare manually. None is needed for this narrowly authorized collection step.

Pre-commit privacy review: pass startup options through the existing one-shot
`Speech.PrivateInit`, with only its redacted handle in the supervised Socket
start specification. Socket's own status redaction does not by itself hide raw
start arguments retained by a supervisor. The test helper closes the handoff
after startup/failure, with the existing bounded expiry as fallback.

## Future authorized execution

The original execution procedure used an operator-supplied PCM file and
expected suffix. The 2026-09-28 fixture update below supersedes that input
procedure. Live selection still requires explicit authorization for its
provider calls.

The test is live-provider-tagged and excluded without explicit selection. The
test setup generates missing fixture inputs before opening the probe connection.
Run this hosted file only with authorization for its provider call. Keep its
exact path in the command so the filter does not select other Deepgram tests.

Retain only the emitted map: `terminal`, `connected?`, `audio_sent?`,
`close_stream_sent?`, `tail_verified?`, `error_free?`, `passed?`. A successful
observation requires `terminal: :normal_or_no_status` and all six booleans true.
An abnormal close is classified without exposing its code/reason. EOF is
`:connection_lost`, missing terminal is `:timeout`, and local process termination
is `:local_teardown`; none passes. Other fixed classes identify invalid input,
wire/order, limits or unavailability. The 30-second acceptance deadline begins
before credential/connection work, after bounded fixture validation. Existing
Socket calls can take up to five seconds; cleanup is separately bounded by the
supervised shutdown. Evidence processed after expiry cannot pass; cleanup does
not change an observation already accepted before the deadline.

No hosted run has been performed. A successful observation still requires profile
review followed by provider final-tail, channel lifetime/acknowledgement, deadline
and usage tests before finite admission. It would not prove every possible server
closure is successful, or distinguish raw empty close from explicit status 1000.

## 2026-09-28 live-test fixture update

The earlier operator-supplied PCM and expected-tail inputs above have been
replaced for the live test. The selected test calls
`Vxpipe.Providers.Deepgram.LiveFixture.ensure!/0` during setup. That helper
uses Deepgram TTS to generate the missing 16 kHz PCM sample for the fixed
phrase “The final word is telescope.” It derives an Opus sample locally with
FFmpeg if needed, and reuses existing files. The expected probe suffix is
`telescope.`. The generated samples remain in the Deepgram provider test fixture directory
for review and a later commit. This makes the first selected run include one
additional billable TTS request when the PCM sample has not been generated.

After filling `~/.config/vxpipe/live_providers.env` from the
[template](../config/live_providers.env.example), run only the probe with:

```sh
bin/livetests run --only live_deepgram \
  apps/vxpipe_call_engine/test/integration/deepgram_flux_close_stream_probe_test.exs
```

The probe’s bounded PCM validation and sanitized result contract are
unchanged. The earlier operator-fixture instructions record the original
design and are superseded by this update.

## Local verification

From the owning child with the same isolated build and two-scheduler settings:

```sh
mix test test/vxpipe/providers/deepgram/close_stream_probe_test.exs \
  test/integration/flux_close_probe_loopback_test.exs \
  test/integration/speech_socket_peer_close_test.exs \
  test/integration/speech_socket_privacy_test.exs \
  test/vxpipe/providers/deepgram/stt_socket_test.exs \
  test/vxpipe/providers/google/stt_socket_test.exs --include integration --seed 0
```

The 26 offline cases and one local-loopback case plus the existing 27 regressions
pass (54/0), including redacted supervisor startup and private-handoff cleanup.
This command deliberately omits the hosted entry point. The initial 24/24
absent-API red, later 26/2 private-startup red, focused greens and exact completed
handles/log basenames are recorded in
[checkpoint labnotes](20260922-2041-flux-close-probe.md).
