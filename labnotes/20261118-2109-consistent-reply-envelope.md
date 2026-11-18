# Consistent reply envelope

User correction: existing assistant history already contains type and participant_id.
DeepSeek copied that envelope; the earlier classification as simply a model failure
was incomplete. User explicitly requests expecting those fields back and rejects
backward compatibility. Require exactly four fields for modern dialogue. Keep
host settlement authoritative and existing history unchanged.

## Evidence and implementation

- Original focused red: 139 tests, 14 failures (12 provider/mode envelope cases,
  decoder envelope case and schema expectation). Identity test: 5 tests, 1 failure.
- Strict-contract red after explicit no-compatibility direction: 7 tests, 1 failure;
  old two-field reply was still accepted. Removed that branch.
- Runtime child suite: 543 tests, 0 failures, 25 excluded, seed 494740.
- Decoder validates exact fields, duplicate keys and bounded attribution, then
  returns existing typed mode/text only. Schema, packaged prompt and repair
  instruction now request the history envelope. Activation identifies the current
  agent independently of prior participant history. Diagnostic fixture provider
  and modern fixture replies updated to match.
- Usage repair fixture previously used the now-valid envelope as its invalid
  trigger; it now uses an invalid type, preserving usage/budget assertions.
- No acceptance waiver, live success or deployment claimed. Earlier release
  candidate predates this correction and must be rebuilt after verification.

Design rationale is recorded in docs/design/universal-agent-replies.md.
Independent Astra xhigh design review supports keeping attribution nonauthoritative;
final implementation review is clean after the transfer fixture correction.

## Review and verification continuation

- Independent Astra xhigh runtime/repair/wire checks: 274 tests, zero failures.
  Activation and tool-room checks: 15 tests, zero failures; model-returned forged
  attribution cannot relabel actual delivered history.
- Review reproduced a stale exact-prompt expectation in the transfer test. The
  fixture now expects the pinned prompt plus the actual source/destination ID,
  including after restart. Independent rerun: 1 test, zero failures, seed 392744.
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  check pass. Full root suite is running.
- Fixed `envelope1` live attempt started after clean review: six remaining-provider
  conversations, unchanged models/tools/scenario/output cap; all outcomes retained.


- `envelope1` completes: 6 tests, zero failures, 10 excluded. All DeepSeek,
  Fireworks and OpenRouter buffered/streamed full conversations pass under the
  unchanged models, tools, output cap and semantic assertions. Exactly 60 step
  records retained in the evidence JSON. No acceptance waiver is needed for
  those cases. Primary Google/OpenAI four-case run is in progress.

- Primary `envelope-primary1`: Google/OpenAI buffered and streamed, 4 tests,
  zero failures, 12 excluded; 40 step metrics retained. Dedicated tag selects
  exactly those four configured cases; independent metadata review confirms it.
- Root attempt 1 loaded the old transfer fixture before the reviewed fix and
  reproduced its known failure. Stopped that obsolete run after preserving its
  log (not a completed successful suite); root attempt 2 starts on the final
  source/fixture revision. The bounded cancellation fixture also keeps its
  partial fragment below the 60-byte cap; independent rerun 5/0, seed 366780.
