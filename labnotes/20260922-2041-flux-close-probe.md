# Guarded Flux close probe

Baseline: `f78caa73`, isolated recognition worktree/branch. Prior checkpoint clean;
new note created with `bin/create-labnotes flux-close-probe`. Parent owns integration
and root gates. This checkpoint permits tests/support and focused docs only.

## Design and tasks before tests/code

Recorded concrete tasks and separate design review in the STS milestone, plus
`docs/flux-close-stream-probe.md`. Re-read the official Flux CloseStream page:
latest updates precede closure; no guaranteed EndOfTurn/summary; unspecified
observable status-less close remains the evidence gap. No SDK audit repeated.

Use existing Flux decoder and Socket send/peer-close callback. Explicit opt-in
must precede credential resolution/connection. Bound input, collection and absolute
deadline; require valid Connected, successful ordered audio and CloseStream-only
sends, expected private tail, no errors and normalized peer close before expiry.
No requirement for an update after finish. Reject EOF/local/abnormal/early close,
limits, missing tail and expired queued terminal. Reports contain only class and
booleans; no raw data or secrets. No production changes or hosted execution.

## Verification chronology

Initial red: owning-child `mix test
test/vxpipe/providers/deepgram/close_stream_probe_test.exs --seed 0`, with
`ERL_FLAGS='+S 2:2'` and `MIX_BUILD_PATH="$PWD/../../_build"` from that child.
Log `vxpipe-flux-close-probe-red.log`; handle 38595, terminal `d4895d`, exit 2:
24 tests / 24 failures, undefined new test-support probe API. This is the absent
implementation red, not a hosted protocol reproduction.

After adding only test-support runner and evidence collector, the same command
passes 24/0. Log `vxpipe-flux-close-probe-green-attempt.log`; handle 32948,
terminal `bb5958`, exit 0. Clock-controlled queued terminals processed at/after
expiry fail, valid evidence strictly before expiry passes. PCM/CloseStream
ordering, callback forwarding bounds, errors, missing/changed tail and opt-in
checks are offline synthetic tests. The finish gate records whether close was
observed after the send was requested, independently of owner mailbox delay.

Added a tagged/skipped hosted entry point with the independent runner gate and
a local-loopback runner integration. The latter actually observes the ordered
binary chunks and CloseStream JSON at the existing WebSock fixture, then supplies
tail/peer close through real Socket. It does not contact Deepgram. The hosted test
file was not executed, even in an unarmed configuration.

Combined focused command, from `apps/vxpipe_call_engine`:

```sh
ERL_FLAGS='+S 2:2' MIX_BUILD_PATH="$PWD/../../_build" mix test \
  test/vxpipe/providers/deepgram/close_stream_probe_test.exs \
  test/integration/flux_close_probe_loopback_test.exs \
  test/integration/speech_socket_peer_close_test.exs \
  test/integration/speech_socket_privacy_test.exs \
  test/vxpipe/providers/deepgram/stt_socket_test.exs \
  test/vxpipe/providers/google/stt_socket_test.exs --include integration --seed 0
```

Log `vxpipe-flux-close-probe-regression-green.log`; handle 84896, terminal
`4ccac6`, exit 0: 52 tests / 0 failures in 16.3 seconds. The two existing Bandit
HTTP-upgrade error messages in the privacy group contain no private data and
do not fail those tests. All handles terminal. No root/native/load/hosted work.

Proportionate verification: formatted the five new Elixir files from the child
(terminal `819df2`, exit 0). `mix help credo` from this child reports task not found
(`85c63f`, exit 1); did not broaden to root. Parent owns root/static gates.
Exact-path format check `89f6b9` passed, as did `git diff --check` (`ffcea5`).
Pre-commit review found raw Socket options in the hosted test child specification;
Socket status redaction alone does not cover that surface. Recorded an additional
milestone task and separate design review before the privacy test/repair: reuse
existing PrivateInit only in test support, verify redacted spec/exact private
delivery and cleanup on failed startup. No shared/runtime changes needed.

Private-startup red: the same single offline-file command reports 26 tests / 2
failures for absent `start_socket/3`. Log `vxpipe-flux-close-probe-private-red.log`,
handle 69254, terminal `74512e`, exit 2. Added a test-support start helper using
existing PrivateInit, then switched both tagged entry points to that helper.
The local-loopback test therefore exercises its real claim/Socket-start path.

Final green: reran the exact combined six-file command above, log
`vxpipe-flux-close-probe-final-green.log`, handle 85078, terminal `0eb39b`, exit 0:
54 tests / 0 failures in 16.3 seconds. All handles terminal. The two existing
privacy-group Bandit upgrade error lines remain sanitized/non-failing.

Final exact-path `mix format --check-formatted` on the two new support files,
offline test and two integration files passed (`04807e`, exit 0); `git diff
--check` passed (`e11b66`). Exact-path staging/cached review covers only the five
new test/support files, two focused protocol docs, milestone and this labnote.
No production code or dependency changes. Parent owns independent review and
broader gates; no root/native/load run and no hosted test invocation.

## Limits

No production files, adapter opt-in, finite flag, parser/dependency or manifest
changes. Byte validation does not infer raw PCM acoustic content/format: an
operator supplies known bounded speech and an exact private suffix in the future
command documented separately. The result has one terminal atom and six booleans.
Only a future authorized hosted run can settle this client/endpoint observation;
even success still needs profile approval and production lifetime/final-tail tests.
