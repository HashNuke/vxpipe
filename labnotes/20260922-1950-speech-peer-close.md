# Speech peer close

2026-09-22. Starting from clean `75dba0ac` on the isolated recognition branch.
Created with `bin/create-labnotes speech-peer-close`. Parent approved only the
internal optional Socket callback, tagged loopback test/probe, existing upgrade
fixture, scoped docs/milestone and this lab. No production adapter opt-in, finite
flag, hosted calls, main/root/native/load work or shared dependency writes.

## Before tests/code

Recorded concrete milestone tasks and separate design review first. Intended
contract: one sanitized observed peer-close callback after earlier frame/ack
delivery, no generic duplicate, code retained despite close-reply failure;
EOF/errors/local close and non-opted-in adapters retain existing behavior.

Dependency inspection found a precondition missed in the earlier interface plan:
`mix.lock` pins mint_web_socket 1.0.6, whose `Frame.into_frame/5` empty-close branch
returns code 1000/reason empty. Socket receives no nil status for that wire frame.
This is not proof that a remote server sent 1000. Do not manufacture `:no_status`
from all normal closes or modify dependencies in place. Notified parent before
tests/runtime changes. The loopback red will preserve the intended distinction;
any broader decoder/connection change requires scope coordination.

Inspection commands: `rg -n mint_web_socket mix.lock` and
`sed -n '345,377p' deps/mint_web_socket/lib/mint/web_socket/frame.ex`.
Read-only handle `57fbf2` completed exit 0. One preceding rg expression had an
unescaped opening brace; corrected before relying on results. No runtime test
had run at this point. Own `_build` resolves inside this isolated worktree.

## Test evidence

All commands below run from `apps/vxpipe_call_engine` with
`ERL_FLAGS='+S 2:2'` and `MIX_BUILD_PATH` set to this isolated worktree's `_build`.
Prefix the shown commands with those assignments when reproducing. Log names
below are portable basenames for temporary diagnostics, not committed artifacts;
choose a local scratch directory when redirecting output.

```sh
mix test test/integration/speech_socket_peer_close_test.exs --include integration --seed 0
```

- Initial red: `vxpipe-speech-peer-close-red.log`, handle `9632`, terminal
  `ccd2e2`, exit 2: 11 tests / 7 failures. Six missing callback failures plus one
  incorrect test assumption: a malformed frame is forwarded as a decoded error
  tuple, not automatically mapped to transport disconnect. Replaced that case
  with actual send failure on a deliberately closed loopback connection; no
  production error-handling change was made to accommodate the assumption.
- Confirmed red BEFORE Socket implementation:
  `vxpipe-speech-peer-close-red-confirmed.log`, handle `7620`, terminal
  `93d7cb`, exit 2: 11 tests / 6 expected missing-callback failures. The empty-close
  failure reports only the decoded code list, `[1000]`, from the existing pending
  queue after a genuine empty peer frame. This proves the information was lost
  before Socket callback dispatch, independently of later hosted questions.
- Implemented only approved optional callback dispatch in Socket, with unchanged
  default/error/local-close paths. No production adapter opts in.
- Post-seam probe: `vxpipe-speech-peer-close-post-seam.log`, handle `69759`,
  terminal `f24d5d`, exit 2: 11 tests / 1 failure. Coded-close ordering, reply
  failure, privacy, EOF/send failure, rejected ack, local close and legacy cases
  pass. Empty-versus-explicit-1000 remains red because of decoder normalization.
  That run was NOT a green checkpoint and was not ready to commit.
- Combined owning-child regression:

  ```sh
  mix test test/integration/speech_socket_peer_close_test.exs test/integration/speech_socket_privacy_test.exs test/vxpipe/providers/deepgram/stt_socket_test.exs test/vxpipe/providers/google/stt_socket_test.exs --include integration --seed 0
  ```

  `vxpipe-speech-peer-close-regression-pending.log`, handle `58284`, terminal
  `47bfe0`, exit 2: 27 tests / 1 failure in 16.0 seconds. Only the same empty-close
  distinction fails; all existing privacy and selected adapter regressions pass.
  All those test handles completed. The implementation/tests/docs remained
  unstaged; no commit was made against that red specification.

The reply-failure regression holds an already decoded real peer close behind a
binary-frame acknowledgement, closes the actual Mint connection through a
synchronized state callback, proves sending its reply fails, then releases the
acknowledgement. No sleeps or hosted traffic; the observed peer code still arrives.

Official primary confirmation of the dependency behavior:
[Mint v1.0.6 Frame.into_frame/5](https://github.com/elixir-mint/mint_web_socket/blob/v1.0.6/lib/mint/web_socket/frame.ex#L360).
Do not fake `:no_status` from 1000. The initially promised raw distinction would
have required a reviewed decoding/dependency approach outside the Socket-only
runtime path. That specification was subsequently rejected as described below.
This primitive cannot establish hosted finite completion or enable selection.

## Historical coordinated repair hold

Parent acknowledged the decoder constraint and is checking newer official Mint
behavior. Runtime changes and new test/build commands are held pending that
decision; the red is retained, with no weakened distinction or red commit.

Verified hooks in the pinned local source: public `Mint.WebSocket.stream/2`
delivers raw `{:data, ref, bytes}` without WebSocket decoding;
`Mint.WebSocket.decode/2` delegates to `Frame.decode/2`. Frame construction
normalizes empty status before extension decode, so an extension cannot recover
it. `Mint.WebSocket.new/5` handles active/passive mode, not close-status policy.
Our `SocketConnection.decode_responses/3` is the single project decode call site,
shared by normal receive and coalesced upgrade bytes. Any approved raw-evidence
adapter would have to live there and cover both paths, without duplicating the
full WebSocket decoder. No such adapter or dependency change is implemented.

Initial repair proposal: an approved dependency version/pin which preserves
empty status in the existing decoded frame. If none exists, a maintained narrow
dependency correction is preferable to a parallel parser. A project-owned bounded
raw framing tracker at the single decode boundary is a fallback proposal only:
it adds framing state, split/coalesced-frame correlation and extra conformance
obligations, so it is not the already-approved Socket-only patch.

Subsequent parent direction supersedes those repair proposals: parent reports
official upstream main still normalizes empty status to 1000 and no obvious
released fix. Parent is considering an honest `:normal_or_no_status` callback
value for decoded 1000, with other codes numeric; Goodall is reviewing that exact
decision. Raw empty-versus-explicit-1000 fidelity was our initial design assumption,
not the milestone requirement to distinguish peer close from loss/local teardown.
No fork or raw parser is authorized. Await approval before changing assertions or
runtime; the recorded reds and current 27/1 outcome remain unchanged. This waiting
pass changed documentation chronology only, with log paths already reduced to
portable basenames. No new build/tests, upstream research or commit.

## Approved normalized-status correction

Parent approved the corrected contract after Goodall xhigh independent design
review. Before editing test expectations or runtime, recorded the decision and
new red/green task in the milestone/research document and corrected callback type:
decoded 1000 becomes `:normal_or_no_status`, other decoded integer codes remain
numeric. Separate empty-payload and explicit-1000 real-wire tests stay mandatory.
The original missing-callback reds and the later 27/1 failure above are factual
history; raw status fidelity was an unsupported specification assumption, not the
user's milestone requirement. No dependency fork or second parser.

This callback proves an observed peer close, NEVER successful application drain.
A future hosted profile must prove the normalized class sufficient after finite
finish. If it requires the lost raw distinction, this seam cannot supply it.
All existing ack/order/rejection/reply-failure/privacy/legacy behavior must remain.
No production adapter opt-in or finite flag is in scope.

Revised test-first cycle, using the same isolated-child environment and 11-test
command above:

- Revised red before mapping change: `vxpipe-speech-peer-close-normalized-red.log`,
  handle `44287`, terminal `abc255`, exit 2: 11 tests / 3 expected failures. Empty
  payload, explicit 1000 and the ack-order case received numeric 1000 rather than
  `:normal_or_no_status`. Other cases passed. Only the declared type/docs and test
  expectations had changed; runtime still used the initial mapping.
- Applied the minimal mapping for decoded 1000. Green:
  `vxpipe-speech-peer-close-normalized-green.log`, handle `17847`, terminal
  `121edc`, exit 0: 11 tests / 0 failures. Empty and explicit 1000 are independent
  actual-wire tests. Format of the four changed Elixir paths completed exit 0
  (`e8da25`) before the combined regression rerun.
- Combined final focused green: run the same 27-test command recorded above.
  `vxpipe-speech-peer-close-normalized-regression-green.log`, handle `99823`,
  terminal `a5b45b`, exit 0: 27 tests / 0 failures in 16.0 seconds. The existing
  privacy lane also logged two Bandit HTTP upgrade errors; ExUnit completed with
  zero failures. No new exclusions or test skips were added.

Portable reproduction from `apps/vxpipe_call_engine`:

```sh
ERL_FLAGS='+S 2:2' MIX_BUILD_PATH="$PWD/../../_build" mix test test/integration/speech_socket_peer_close_test.exs --include integration --seed 0
ERL_FLAGS='+S 2:2' MIX_BUILD_PATH="$PWD/../../_build" mix test test/integration/speech_socket_peer_close_test.exs test/integration/speech_socket_privacy_test.exs test/vxpipe/providers/deepgram/stt_socket_test.exs test/vxpipe/providers/google/stt_socket_test.exs --include integration --seed 0
```

All handles above are terminal. No shared build/deps writes, full root/native/load
gates, hosted execution, main integration, dependency changes, production adapter
opt-in or finite capability enablement. Hosted completion remains unproven/open.

Final checkpoint checks: exact four-path `mix format --check-formatted` passed
(`d9f07a`, exit 0); `git diff --check` and staged diff checks passed. Reviewed all
seven exact staged paths (`9c6eaf`, `b56627`) including source, real-wire tests,
fixture changes, milestone/design chronology and this lab. Log references use
portable basenames; no local absolute paths, dependency/build artifacts or secrets
are included. Commit follows this focused green and cached review, before any
parent-owned broader gate or independent final-source review.
