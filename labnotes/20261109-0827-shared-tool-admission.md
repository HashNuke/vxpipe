# Shared tool admission

## Scope and starting evidence

Continue the shared participant milestone at `4f3a72f3` (clean checkout, pushed;
7/20 tasks complete). The previous turn made progress: ordinary interruption and
MCP transfer lifetime now pass; all root gates passed with 5,137 tests. This
checkpoint implements C3's shared blocking/nonblocking conversation rule without
provider-specific business logic or a second executor.

## Reproductions

Compiled-room ordinary/duplex tests require blocking tools to hold new input,
nonblocking tools to permit it, and completion of one background tool to leave
another blocker intact. Additional tests exercise provisional admission, retained
input hold until registry consumption, stale forwarded scope and dropped PCM.
After correcting the fixture's host-tool static-name constraint and adding a
room barrier before inspecting consumed state, the baseline reproduced eight
failures in ten cases (seed `349359`).

Astra design review identified two required boundaries: local provider acceptance
must precede registry consumption and only the latter can release business input;
every provisional request needs a terminal response. External/hybrid activity
also needs to remember a suppressed start through its end. Two of four activity
tests reproduced forwarding a suppressed utterance's start and tail after the
tool completed (seed `188358`).

## Implementation

Move the existing conversation reducer to Tool.ConversationAdmission and reuse it
from LLM registry snapshots and native bounded pending associations. No registry
RPC runs per PCM frame. Native forwarded requests provisionally block until the
room confirms their accepted mode. Keep sibling tool events independent of the
caller-input gate. Native sessions already retain the original model function
call while unrelated input proceeds; no extra interim function result is sent.

Owner-only admission and finish operations retain the existing pending record
until registry acknowledgement. A locally accepted result retires transport-turn
tracking but cannot be sent twice or release a different blocker. Cancellation
retains the admission mode while existing bounded outcome handling runs. Scope-
invalid forwarded requests fail explicitly rather than leaving an orphaned hold.

Blocking frames acknowledge discard; continuous sessions receive equal-duration
silence. Held text is rejected and never queued for replay. An external/hybrid
start suppressed during blocking remains suppressed through its end even if the
tool finishes midway; an already-forwarded start can still receive its end.
Transfer holds, policy validation, output-origin fences and unsafe-input checks
remain separate.

Existing publication-only fixtures now obtain real provider call associations
before room admission. Tests issuing a new request after a public completion
wait for the room's registry acknowledgement, since business completion precedes
consumption. The native failed-transfer fixtures retain the same recovery test.

## Verification

Initial ten focused admission cases pass after implementation. Updated room/MCP
fixtures pass: 47 tests, zero failures (seed `679389`). The initial checkpoint
remained 7/20 while independent review and expanded acceptance were pending.

The mixed-mode LLM case passes with existing pending-invocation awareness: finishing
background work leaves a separate blocking invocation held (4 tests, seed `334114`).
The expanded initial run found one existing Google fixture expecting provider
`:busy` instead of the new acknowledged-discard PCM contract; its no-new-wire-origin
assertion is preserved with the corrected acknowledgement expectation.

Independent review found three concrete defects, reproduced before fixes:

- A rejected call whose provider association was cancelled could retain an orphaned
  provisional blocker; the room ignored rejection delivery failure.
- Removing a rejected sibling could leave an accepted sibling's transport turn in
  the active-turn set. Both tests failed at seed `927490`.
- Production hybrid STT onset never reached capability admission, allowing tail
  PCM after the tool finished mid-utterance. A real room/STT-origin reproduction
  failed at seed `682219`.

Rejection delivery now fails explicitly. Pending updates and removal share one
status-aware transport-turn calculation. Hybrid start follows the existing
ingress path to local admission; it sends no provider start, preserving provider
onset. All seven review/activity cases pass (seed `507778`). Source re-review
reports no remaining actionable findings and approves closing only C3's
conversation-mode task, bringing the milestone to 8/20.

The expanded 621-test lane exposed seven origin fixtures selecting hybrid while
asserting external provider-start behavior. Those seven explicitly select
external now; the real hybrid test still asserts provider-owned onset. The
32-test origin lane passes after this correction. No provider implementation changed.

Final umbrella verification: **5,158 tests, 0 failures, 371 excluded**, seed
`226773`; the Call Engine portion has 2,376 tests, zero failures and 100 excluded.
All four other root checks pass (format, warnings-as-errors compilation, strict
Credo, unused dependencies). Lean build/oracle/replay passes, seed `671547`.
Changed durable documentation links resolve and `git diff --check` passes.

The preceding goal turn made progress: it reproduced and fixed all three review
findings, obtained clean source/test review, and started the full root verification.
This continuation polled that same live process through completion; it did not
restart verification merely because output observation timed out. No deployment
or provider live test was performed. Completion, replay, saved-connection races,
shared execution bounds and final conformance remain open.
