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

- Refreshed room acceptance: combined `envelope-room1` 4 tests, zero failures,
  seed 519372; both real Hangup actions and both Chrome/Deepgram-TTS calls pass.
  Desktop/phone screenshots inspected for both integrations. All transcript/TTS
  matching and Google native tool-mode assertions executed. C3/E2 complete.
- Implementation checkpoint `03e449c0` pushed. New release assembled; 14 packaged
  module code digests match production compilation, strict four-field probes pass.
  Candidate image built; independent image audit pending. No deployment yet.

- Independent F2 image audit is clean: 6,983 files including 6,140 BEAMs match
  assembled release exactly. Extracted decoder rejects old two-field replies,
  attribution remains nonauthoritative, actual activation identity is supplied,
  legacy behavior and future-model admission remain intact. Packaged prompt
  matches source; 14 executable digests match production compilation.
  Candidate: vxpipe:universal-replies-03e449c0, image
  sha256:5b9e40183fd29c2895f518b45ab6a1b15ad9ba11d27e29a249708a88fff4dd0c.
  Never-started disposable audit container removed. Running service unchanged.

- Root attempt 2 received SIGTERM before the Call Engine summary. Although its
  wrapper reported exit 0, the incomplete run is not passing evidence. Cause is
  not established; independent image-audit cleanup touched only its never-started
  disposable container. Root attempt 3 runs in a dedicated persistent tmux
  session with an explicit completion/exit record to avoid tool-session lifetime
  affecting verification. No production code changed for this interruption.

## Final acceptance

Root attempt 3 exits 0 at 21:43:13 UTC: 5,892 tests, zero failures, 409 excluded,
seed 914326, all ten umbrella apps complete. Independent Astra xhigh E4 review
is clean. Final format/compile/strict-Credo/unused-dependency checks pass;
production asset build includes a passing type check. No source-cutover or speech
state transition changed, so no extra Lean lane is required. Readiness 22/24;
only deployment and final release evidence remain.

Deployment plan independently reviewed: exact candidate/recovery image guards,
full-suite terminal guard, existing systemd packaged migration preflight, public
health and packaged frontend asset SHA256 checks. Isolated synthetic Room smoke
rehearsed against packaged release; creates no saved specs/credentials, makes no
external calls, completes a real turn with host attribution and orderly teardown.
The smoke uses release eval in a separate VM inside the deployed container because
service distribution is disabled; public health/assets verify the running service.
