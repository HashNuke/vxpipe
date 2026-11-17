# Implement structured messages

Status: checkpoints A/B complete. The full milestone remains active;
13 C/D task groups remain open. Earlier sections record implementation history.

## Scope and process

Implement [the milestone](milestones/structured-agent-messages.md) in its approved
order. Use red-green-refactor and retain existing dirty design/planning work.
The user requires GPT-6 Astra xhigh review at every checkpoint, repeated until
no issues remain. Findings need validated reproduction steps or failing tests.
No commits requested. Do not read or modify the live-provider environment file.

## Initial implementation

- Ran bin/setup successfully for this checkout; dependencies/assets and dev/test
  migrations completed. Existing .env was preserved. No live provider calls.
- Added a trusted host Input value for participant identity/message/mode snapshots
  and the greeting_request/idle_timeout catalog. Literal human text is never
  decoded as an envelope. Only fixed atoms become mode/event strings.
- Constructors validate text/identity/mode and bound the encoded envelope to
  64 KiB. Inspect omits content. The request's configured byte bound still applies.
- Request/Session accept constructed inputs on the matching caller/engine path.
  The existing request runner retains their encoded content unchanged. Legacy
  caller strings and native engine/tool observations keep their existing path.
- The first increment added only the runtime boundary. The following increment
  wires participant/platform input through configured Call Engine calls; final
  dialogue, supported assistant history, archive and viewer work remain incomplete.

## Evidence

- Before implementation, the five focused structured_input_test.exs tests all
  failed on the absent Input module (seed 264365).
- After implementation, the five tests pass (seed 233343), covering origin
  matching, bounded/invalid inputs, literal JSON-shaped speech, Unicode/quotes,
  session history retention and real ReqLLM request projection encoded once.
- The Agent Runtime suite passes: 113 tests, zero failures, eight excluded
  (seed 755689). No provider networking in this lane.
- Root format, compile warnings-as-errors, strict Credo and unused-lock checks
  pass. An initial formatter invocation used root-relative paths from the child
  directory and found no files; reran it successfully from the root.
- Astra xhigh reproduced one P2: Date/Time structs satisfied is_map(data) but
  encoded as strings in platform event data. Added the exact regression, confirmed
  one expected failure (seed 787817), then rejected structs at construction.
- After the correction, the runtime suite passes: 114 tests, zero failures,
  eight excluded (seed 423309). Astra independently reran 21 structured-input,
  contract, continuation and provider tests and found no remaining reproducible
  issues in this increment. This is supplementary review, not checkpoint acceptance.
- The initial root suite passed under exec session 93753 (seed 63305); it covered
  the first increment before subsequent Call Engine changes. The post-fix four
  other root checks passed (session 28512 completed). Do not treat this older
  suite as proof of later changes; current revision verification is below.

## Next work

Complete supported assistant speech settlement/typed history and attributed
transfer/compaction, nested retention, versioned archive projection and Console/
core/react display mapping with focused failing tests. Finish configured-session,
browser and required root/Lean checks, then run the full Astra checkpoint review.
The input and initial mode boundaries described below are already implemented;
all checklist acceptance gates remain open until the full requirements are met.

## Call admission and mode increment

- Red tests failed as expected for a compiled call interpreting JSON-shaped human
  text as the whole input, and for the missing internal queued-input field (seed
  630519). The mode-lifecycle test failed on missing TurnState.mode (seed 483769).
- SendText now carries an internal model_input, excluded from its constructor
  options. RoomAuthority constructs it after authorization and before interruption;
  STT captures the receiving agent mode at onset and retains it through endpoint.
  The coordinator passes the same value through its existing bounded queue.
- TurnState owns mode derived from admitted main output. Pending inference stays
  listener; main text admission enters speaker through existing output ownership;
  matching settlement/cancellation removes that output. Stale output callbacks do
  not create a new turn or relabel another output. This is the A legacy-result
  slice; C still owns validating mode/message intent and E owns actual cues.
- ActiveRequest uses explicit engine-origin greeting_request/idle_timeout content.
  Native completion and standalone legacy coordinator inputs retain their strings.
  Updated compiled-call assertions for the intentional new participant envelope;
  transferred older plain history still remains plain until its attribution work.
- The initial three focused tests passed (seed 622911). A real compiled-call
  test additionally confirms speaker mode is captured before old output is
  interrupted and the subsequent settled call returns to listener (seed 45222).
- Broader affected Call Engine regression lane: 150 tests, zero failures, eight
  excluded (seed 322382). Earlier failures were five outdated wire assertions;
  one assertion wrongly decoded native engine observations and was restricted to
  the exact latest participant input. Preserve these distinct protocols.
- Astra additionally reproduced an audio fixture regression: TestEchoModelProvider
  echoed the entire new envelope. Independently confirmed the existing audio-turn
  test failed (seed 554888), then adapted the fixture to simulate reading the outer
  participant message while leaving nested human JSON literal. The 30-test audio,
  text, TTS, speech-expansion and transfer lane passes with that correction.
- Astra reproduced a further P2: detached completed generation left a stale
  admitted turn in speaker mode. Copied the compiled-room reproduction into the
  repository and independently confirmed failure (seed 3800). Detachment now
  retires output eligibility for only that connection while retaining separate
  tool/turn bookkeeping. Late callbacks cannot readmit or emit retired output,
  including after connection-ID reuse.
- The combined affected Call Engine lane passes 171 tests, zero failures, eight
  excluded (seed 330941). Astra re-review independently passed the original repro
  and connection-ID-reuse/late-output variant plus mode/room tests, finding no
  remaining reproducible issues. Copied the reuse variant into the repository
  as lasting coverage. This does not complete checkpoint A review/acceptance.
- Full A remains open.
  Root format/compile/Credo/unused-lock checks plus Lean passed under exec session
  39652; Lean rebuilt the oracle, checked drift and passed the replay (seed 424510).
  Bounded logs are under vxpipe-structured-{format,compile,credo,lock,lean}.log.
- After the retirement correction, current root verification is running under
  exec session 32457 (full suite seed 445399), with logs under
  vxpipe-structured-*-current.log. The static/Lean portion passed. Resume
  that exact suite handle; the older root handle 93753 has completed.
- Final mode/room tests after copying the reuse test pass: 10 tests, zero failures
  (seed 695316; exec session 27526 completed), with output in
  vxpipe-structured-mode-final.log.

## Supported assistant history increment

The user added an explicit review requirement: verify placement/SRP/dependency
ownership as well as behavior, and validate every finding with reproduction
steps or a failing test. This applies to every checkpoint review and re-review.

- Rejected replacing already submitted generated assistant messages: retain input
  on admission and stage final dialogue outside reusable conversation instead.
  SessionConfiguration now supports generated (legacy default) or host_settled
  history. In the latter mode, cancellation keeps admitted input and native tool
  facts; one pending output gates the next request until exact settlement.
- Message constructs/validates attributed spoken content. Session owns sequencing;
  Coordinator.OutputSettlement owns correlation and the queue gate;
  RoomAuthority.OutputHistory owns completed-segment delivery evidence. Configured
  LLM activations select host_settled; standalone graphs retain their default.
  No provider tool envelope, platform completion format or STS protocol changes.
- Fixed greetings stage output without requesting the model, then append supported
  speech only at settlement. Ordinary failures/interruption close the gate with
  only confirmed segments; zero/unknown delivery appends no speech. Text-only
  output is retained as admitted text; expected but unplayed TTS is excluded.
- New runtime tests initially failed (four failures) on missing APIs/configuration.
  Their first helper also omitted the existing required pending_context_source;
  corrected that fixture. Added coordinator-gate and typed fixed-greeting red
  tests before implementing those paths. New typed history required updating
  eight existing protected-greeting assertions to inspect the spoken envelope.
- Found and red-tested output-budget mismatch (seed 546719): using the input
  envelope's 64 KiB limit rejected valid larger/escaped output. Output constructor
  now accepts the configured raw output limit; validation bounds encoded JSON
  before decoding and checks the raw text separately. Astra independently
  reproduced the same issue and verified its fix.
- Final runtime suite: 119 tests, zero failures, eight excluded (seed 236981).
  Tools/protected-opening lane: 65 tests, zero failures. Consecutive/queued
  model-context lane: five tests, zero failures (seed 537358).
- The real TTS prefix test confirms next-model history contains only completed
  First. after Second. is interrupted. The original line selection accidentally
  ran the preceding fixed-greeting test; Astra caught that evidence error. Also
  corrected proxy readiness to await the relayed room-id acknowledgment. The
  actual prefix test at :1213 passes (seed 828183), independently re-run by Astra.
- Astra reproduced a P1: an async completion finishing with its source detached
  had no public TurnState and never closed its history gate. Copied its repro into
  the repository, confirmed failure, then added current-capability, scope-checked
  untracked settlement with no speech. It still checks exact coordinator identity.
  Tool-room/coordinator lane passes 34 tests. Astra re-review passed the original
  repro and an additional stale-callback test, with no remaining reproducible
  issues and no validated SRP/dependency-placement findings in this increment.
- The earlier root suite (handle 32457, seed 445399) completed with 13 Call Engine
  and 16 Gateway failures. These exposed fake-model parsing/raw-history assertions
  left behind by structured input. Updated the scripted tools fixture and affected
  assertions while preserving raw-content negative privacy checks. Relevant Gateway
  phone/WebRTC lane now passes 98 tests, zero failures, one excluded (seed 210064;
  handle 64531 completed). Call Engine full suite finished: 2,464 tests, one
  failure, 100 excluded (seed 824908; handle 91741 completed). Its test files were
  loaded before the proxy-readiness correction; that was its sole failure and
  the corrected exact TTS-prefix test independently passes, as recorded above.
  Do not claim a fully green current umbrella suite from that result.
- Current root format, compile warnings-as-errors, strict Credo, unused-lock and
  Lean checks pass (handle 19496 completed; Lean seed 286080). A fresh current-
  revision root suite is running as handle 87183, with full log
  vxpipe-settled-root-final.log. Resume that exact handle before rerunning.

All A checklist acceptance gates remain open. Remaining scope includes typed
transfer/summary projections, archive retention/version compatibility, viewer
integration/browser inspection and full current-revision verification/review.

## Transfer history and packaged summary instructions

- Added a failing SpokenHistory boundary test before changing its APIs: actual
  admitted SendText and completed TTS requests now retain trusted identity and
  original mode snapshots. Legacy string/map entries remain literal and retain
  their existing projection. STS legacy input paths remain unchanged.
- Updated real input/playback owners to pass those objects rather than dropping
  attribution. Full compiled transfer/re-entry assertions now verify structured
  inherited input. Spoken/transfer tests pass: 14 tests, zero failures (seed 60784).
- Added a red large transferred-speech seed test. SessionConfiguration now uses
  configured output bounds for validated typed assistant history, including JSON
  expansion, while retaining existing bounds/literal handling for legacy strings.
- Host-settled compaction now retains typed conversation_summary/text without
  speech or playback diagnostics. Generated-history sessions keep their original
  summary wrapper. The configured compaction-room test checks the actual summary
  instructions, typed retained summary, protected input and absence from archives.
- Added Prompt as the Agent Runtime-owned packaged-source/revision boundary.
  Moved the three editable sources into app priv/prompts and left documentation
  links at the former draft paths; no duplicate instruction strings remain.
  Only summary instructions are wired here; shared/LLM composition remains C.
- ModelContextCompactor.new snapshots summary source at activation configuration;
  the default compactor uses it lazily. Missing/invalid/oversized assets fail the
  relevant configuration; arbitrary custom callbacks are not forced to load them.
- Initial prompt/typed-summary tests failed as expected: three failures out of
  nine tests before implementation. The focused combined runtime slice passed
  17 tests (seed 77169), and the runtime suite passed 123 tests (seed 941490).
- Astra reproduced one P2: explicitly selecting the built-in compactor bypassed
  the default pinning path. Added a permanent failing configuration assertion,
  then normalized recognized built-in state through ModelContextCompactor.pin.
  Invalid explicitly supplied snapshot markers now fail instead of being replaced;
  already pinned state and unrelated custom callback state are preserved.
- Astra independently re-ran the actual file-edit repro plus bounds/configuration
  tests: six tests, zero failures (seed 918813), no remaining validated findings.
  Ownership review confirms runtime owns prompts/envelopes, configuration delegates
  built-in normalization to its owner, and Call Engine owns attribution/evidence.
  No production release image was assembled or claimed by this review.
- Current post-fix verification passes: runtime suite 124 tests, zero failures,
  eight excluded (seed 831263); transfer/compaction/tool-room slice 24 tests, zero
  failures; strengthened configured typed-summary case one test, zero failures
  (seed 875267). Root format, compile warnings-as-errors, strict Credo, unused-lock
  checks and Lean pass (Lean replay seed 71249). Handles 58938 and 78096 completed;
  there is no pending suite to resume from this increment.
- Earlier umbrella verification handle 87183 has now completed: 5,335 tests,
  zero failures, 385 excluded (log vxpipe-settled-root-final.log). It loaded
  test/runtime code before this transfer/summary increment; it is a verified
  baseline, not a claim that the latest increment has passed the full umbrella.

Checkpoint A remains open. The increment below adds archive/viewer compatibility;
full checkpoint acceptance/review and B/C/D remain in the original scope.

## Archive and viewer compatibility

- Archive.MessagePayload defines structured_agent_message_v1 within existing fact
  payloads. Writers store decoded content with trusted identity/order/correlation
  columns unchanged. Missing markers retain legacy text literally; unknown/null
  versions and invalid/non-speech content never fall back to speech. Both forms
  share shape, identity and size validation. No migration, backfill, outer schema
  change or immutable-publication rewrite.
- Recorder keeps accepted input snapshots. Generated output carries explicit
  intent; legacy/STS event shapes remain valid. Calls owns authorized transcript
  selection; Console owns display projection. Both retention owners remove nested
  text-bearing keys. Native tool facts keep their original shape and policy.
- Codec/retention tests failed on missing APIs; writer failed4/1 and presenter15/1
  after correcting a fixture's absent map key. Green archive17/0, writer4/0,
  presenter15/0, Calls history/retention12/0 and persisted source/publication4/0.
  Persistence proves mixed formats, replay deduplication, trusted columns and
  deterministic publication bytes/digests.
- Console/Core carry optional agentMode/outputPurpose. React labels backchannels
  and omits blank speech bubbles; input mode does not turn human speech into a cue
  or change media state. Unicode ranges and Core refresh replay preserve text and
  metadata. Decoder initially failed1/11; React initially failed2/6. Corrected a
  test query when highlighted text was split across DOM nodes.
- Astra reproduced a P2: stored maps bypassed the16MiB encoded-JSON bound. Confirmed
  repro1/1 failure (seed914205); lasting bounds/escaping test red5/1 (seed289284).
  Validation now checks bounded raw strings and canonical encoded size. Archive17/0
  (seed139469), original repro1/0 (seed853691). Independent re-review passed10/0
  archive/port,4/0 publication and12/0 Core/React with no remaining validated
  behavior/privacy/compatibility/SRP/dependency-direction finding in this increment.
- Inspected incumbent and synthetic listening-cues Storybook with headless Chrome
  through agent-browser at1280px desktop/390px phone, dark/light. No horizontal
  overflow; readable14px cue label and unchanged interrupted-prefix highlighting.
  Astra independently checked1440px/390px dark/light. This is synthetic UI evidence,
  not audible cues or a provider call. Chrome required --args --no-sandbox in this
  environment; non-tty Storybook exited, and a PTY restart restored inspection.
- Impeccable detector reported pre-existing CSS color/bounce advisories outside
  changed lines. New label uses existing tokens and no new animation.
- Workspace client build/typecheck and45 tests pass; Console asset typecheck/lint
  and1142 tests pass. Existing SetupDialog hook warning remains, zero lint errors.
  A client suite raced build dist cleanup; serialized rerun after build passes.

## Main summary interpretation

- A configured request initially showed only authored instructions (red1/1,
  seed814895). Host-settled LLM graphs now compose packaged shared instructions
  with authored instructions into the immutable session child spec. Restarts keep
  the text snapshot. Legacy generated sessions keep their instructions. Missing
  sources fail configuration. Final-response overlay/profile and STS rollout stay C.
- Adapted compaction archive assertions to the explicit new payload marker while
  retaining negative checks that summaries never become participant speech.
- Configured compaction/activation tests pass7/0 (seed854359). The first archive/
  shared-prompt umbrella run (exec14002) completed with12 Call Engine and6 Gateway
  failures. Most were old exact authored-prompt matches and top-level text-payload
  assertions. Updated them to exact shared-plus-authored instructions and explicit
  versioned payloads, including negative readiness assertions. Kept privacy checks.

## Complete A review and final acceptance

- Astra reproduced a P2 through an isolated packaged-app directory: Session restart
  in the same activation reloaded edited default compactor instructions. Confirmed
  red1/1 (seed225853), copied the lasting activation regression, and pinned compactor
  configuration in Session.child_spec through its owning SessionConfiguration.
  This also protects ordinary supervised sessions. Custom callbacks/disabled
  compaction retain their existing state/options; invalid configuration fails.
  Regression1/0 (seed586173). Independent re-review: activation8/0, runtime124/0
  with8 excluded, and four extra child-spec cases; no remaining validated issue.
- Full A review identified evidence gaps separately from bugs. Added actual
  provider projection for platform, spoken-assistant and summary shapes with
  Unicode/quoted strings (runtime7/0, seed221518). The TTS-prefix test now sends
  STT onset, waits for old-output interruption before endpoint, and confirms the
  originally captured speaker mode reaches the model. New fixed-greeting0ms/20ms
  detachment/reconnection cases retain no unsupported speech and make no greeting
  inference. Opening suite37/0.
- Added outgoing answered-callee idle_timeout capture; outgoing/onset selection2/0
  (seed746519). Two-human TTS interruption now captures real model requests and
  confirms both trusted IDs and listener/speaker snapshots (3/0). A new all_spoken
  transfer case plays source TTS and proves the original speaking agent survives
  into the real destination request. Transfer/configured-archive lane42/0.
- Astra independently reran provider7/0 (seed942626) and42 opening/onset/outgoing/
  multiple-human/transfer cases (seed366473). It confirmed every previously missing
  A acceptance case and no new reproduced defect/SRP/dependency issue. A now awaits
  only final root gates and evidence recording; do not mark it complete yet.
- Gateway's first focused rerun had four failures: two more authored-prompt helper
  matches plus two transient phone-opening failures while another media suite was
  active. Updated the helper matches without weakening assertions. The isolated
  failed-case selection passes8/0 in64.6 seconds. Avoid competing Gateway/media
  suites during final umbrella verification. The transient prior results remain
  recorded; no production harness workaround or timeout change was made.
- Current isolated final static/Lean/root sequence is exec5239, with logs named
  vxpipe-message-a-*. Static gates and Lean passed; full tests are running. Resume
  that handle. B/C/D implementation remains open. A draft B failing provider-prefix
  test exists only in temporary storage and confirms pending-state changes mutate
  the current system prompt; no B production code has changed.

## Checkpoint A completion

- Final isolated root sequence exec5239 completed successfully: 5,358 tests, zero
  failures, 385 excluded across all 10 applications (seed 739852). Formatting, compilation with
  warnings-as-errors, strict Credo, unused-lock and Lean gates all pass. The suite
  includes the final pinning fix, typed archive assertions, exact prompt fixture
  matching and added acceptance evidence. No competing media suite ran.
- Complete A Astra xhigh review and re-reviews have no remaining validated finding
  or missing acceptance evidence. All ten A task groups are now checked. The index
  remains unchecked for the overall milestone; B7/C8/D5 are the 20 remaining groups.
- Frontend evidence: workspace 45 tests and build/typecheck, Console 1,142 tests and
  typecheck/lint pass; existing unrelated SetupDialog warning remains. Synthetic
  rendered dark/light desktop/phone checks passed. Browser and Storybook closed.
- No commits, deployments, live network-provider calls or model files/weights added.
  B starts next; its two temporary red tests demonstrate pending-state system
  prompt mutation through both prepared context and captured actual Google JSON.

## Checkpoint B — stable tool history

- Confirmed the only LLM pending inventory writer was ReqLLM.RequestProjection's
  mutable system suffix. ModelContext already rejects that reserved key from
  transient sources. InvocationRegistry and PendingContext remain private control
  data, including compaction protection for unresolved native relationships.
- Added actual captured Google JSON wire-prefix/signature coverage plus a matrix
  with/without system messages, variables and each pending lifecycle status. Changed
  the token estimate contract to ignore host-only pending state. Runtime red lane:
  10 tests, four expected failures (seed 452286). The configured slow-tool prefix
  test initially had a test-helper atom/string-key mismatch; corrected the fixture,
  then reproduced the intended system-prefix failure (seed 550226).
- Removed only pending inventory serialization and its estimated token cost.
  Business variable/transfer context, native messages, submission acknowledgments,
  completion observations, execution admission/deadlines and registry state remain
  under their existing owners. ModelRequest documents its host-only control field.
- Focused runtime 10/0 (seed 89046), runtime suite 127/0 with eight excluded
  (seed 441996), configured room suite 9/0 (seed 458262). The slow-tool case now
  compares provider-encoded prefixes through acknowledgment, unrelated input and
  completion, retaining the original opaque signature and native responses.
- Expanded tagged Gemini interoperability to native call/ack, unrelated input
  while running and a later engine-supplied result. First attempt failed before
  networking because the older fixture supplied temperature=0 to the pinned modern
  model. A safe configuration probe confirmed model resolution and nonblank
  credentials while exposing no credential values; only that generation option
  was invalid. Removed it from the test fixture, preserving production's strict
  rejection of unsupported parameters. No provider env file was read or modified
  directly; the authorized runner loads it in its child as documented.
- bin/livetests selected Gemini case passes: one test, zero failures, two excluded
  (seed 938019), four streamed rounds with real provider usage in 6.8 seconds.
  This is provider interoperability plus the deterministic configured-room test,
  not a claim of a live telephony or end-to-end TTS call. No cache-hit claim.
- B's seven groups remain unchecked pending full requirement/review audit and
  current root verification. C/D remain unimplemented.

- Existing execution/supervision/compaction/shared-tool lane passes 90 tests, zero
  failures. Added ContinueAgent owner-level checks for the exact trust preamble and
  completed/failed/unknown nested outcomes (four adapter tests pass, seed 286055).
- Full B Astra xhigh audit mapped every group to the new wire tests and existing
  owner-level native acknowledgment, completion ordering, interruption, retry,
  duplicate suppression, recovery and teardown checks. No reproduced defect or
  remaining evidence gap apart from final root verification. Independent runtime
  127/0, eight excluded (seed 830724), and lifecycle/compaction/shared-contract
  87/0 (seed 991419). It inspected the live Gemini evidence without repeating
  paid requests. Placement/dependency review is clean.
- Isolated B final root sequence exec17616 is running. Static gates pass; resume
  the handle before rerunning. No B speech/source state machine changed, so Lean
  is unchanged from A's passing lane. B is not checked off until the full root
  suite passes and this evidence is recorded.

## Checkpoint C preparation while B verification runs

No C production code or activation has changed yet.

- PreparedCallFactory reparses immutable revision.source for each new call; old
  published profiles cannot be preserved solely by a default on a new participant
  struct field. CallSpecRevision already has compiled_metadata for pinned validation
  metadata. Publication/preparation/recovery must explicitly distinguish old source
  from new profiles without rewriting historical revisions. The concrete design
  will be tested at those owners before implementation.
- The installed Elixir JSON.decode/3 accepts decoder keyword options; a custom
  object_finish callback can preserve duplicate fields instead of Map.new silently
  retaining the last value. A local decoder-only experiment confirms duplicate
  pairs and trailing input remain visible. This supports strict reply validation
  using the standard library; a regex or extra JSON dependency is unnecessary.
- Current primary provider references: [Google structured outputs](https://aistudio.google.com/docs/structured-output#tools)
  documents schema/tool combinations for Gemini 3/4; nullable string types and
  additionalProperties are supported, while some length/count constraints still
  require application validation. [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
  requires declared required fields and additionalProperties:false, with nullable
  union types available. These are implementation references, not proof that this
  app's selected adapter/profile already sends or accepts the common reply schema.
  C still needs actual adapter wire/provider acceptance and strict parsing.

- Preferred C compatibility approach to validate next: capture a protocol/prompt
  snapshot in new revision.compiled_metadata, then explicitly pass it through
  preparation/plan/startup/transfer/recovery. Missing metadata on older published
  revisions selects legacy replies; do not infer modern defaults when reparsing old
  source. Keep standalone inline hosts' legacy default and use the explicit pinned
  protocol for newly published configured app calls. This may avoid a new public
  call-spec field or schema-version migration. No new source property, metadata
  format or runtime behavior is implemented or accepted by this note yet. Tests
  must prove old publications/digests stay intact and new configured calls select
  the validated contract before adopting the approach. Store the canonical prompt
  bundle once per publication; provider/runtime code owns its parsing/composition.

## Checkpoint B completion

- Final isolated sequence exec17616 completed successfully: 5,361 tests, zero
  failures, 385 excluded, seed 352487, across all ten applications. Formatting,
  compilation with warnings-as-errors, strict Credo and unused-lock gates pass.
  B changed no speech/source state machine or UI; A's formal and rendered evidence
  remains applicable. No concurrent media suite ran during final verification.
- All seven B groups now pass their acceptance gates, with clean full Astra xhigh
  behavioral and placement review plus tagged Gemini interoperability. Checked
  those groups; the overall index remains unchecked. C8/D5 are still unimplemented.
  No cache-hit guarantee, commit, deployment or model-weight artifact is claimed.
- C's notes above are preparation only. Resume by testing its strict reply parser,
  native tool separation, prompt/schema snapshot ownership and old-publication
  compatibility before enabling the common response format.

## Checkpoint C implementation in progress

- Wrote failing strict Dialogue and streamed Session tests first: seven failures
  for the absent parser/protocol configuration in message-c-parser-red.log.
  Added runtime-owned Dialogue with exactly agent_mode/message, duplicate-key
  rejection, nullable listener output and speaker/null rejection. Structured
  deltas remain bounded but are not forwarded; final validation returns a typed
  result distinct from legacy output strings. Tool-round prose/metadata remain
  native history, separate from final speech. Cancellation/deadline/failure and
  output bounds remain owned by the existing request lifecycle.
- Publication compatibility tests failed first on missing agent_protocol metadata
  (message-c-publication-red.log). New immutable revisions now capture a validated
  prompt bundle in existing compiled_metadata; preparation pins it before the
  plan digest. Absent historical metadata/plans stay legacy. No new public source
  property, column, migration, model artifact or default-only cutover was used.
  Runtime owns normalized prompt hashing/composition, Call Engine owns plan/profile
  admission, Calls owns revision persistence. Canonical assets stay packaged once.
- The configured native-tool room test failed first because its request remained
  legacy (message-c-room-red.log). It now verifies actual structured main output,
  native call prose/signature retention, valid silence, explicit cue suppression
  and later completion. The real synthesis-boundary test verifies no partial JSON,
  null/cue or malformed response reaches TTS; later valid output remains usable.
  TTS lane: four tests pass, seed 795353, message-c-tts.log.
- Astra xhigh interim C review found two reproduced P2 issues. A non-JSON NBSP
  suffix passed String.trim; the permanent parser regression failed first, and
  exact JSON whitespace/end handling fixes it. RuntimeGraph also replaced invalid
  explicit built-in compactor state while pinning publication instructions. The
  permanent activation regression failed first; runtime CompactionConfiguration/
  ModelContextCompactor now validate/pin the state, while Call Engine only supplies
  the pinned summary prompt. Explicit custom callback state remains untouched.
  Both original reproductions and permanent cases pass. Interim re-review reports
  no remaining validated behavior or placement finding, and does not close C.
- Independent review evidence: parser/session/protocol/provider 25/0, seed585058;
  compactor reproduction/activation 3/0, seed933528; publication 16/0, seed157059.
  Own activation/prompt/tool room lane 13/0, seed10638. Publication lane16/0,
  seed928176. Full Agent Runtime suite142/0, nine excluded, seed380291.
- The first real streamed schema probe exposed ReqLLM's synthetic structured_output
  call; after filtering its exact isolated validated artifact, another probe caught
  Google.ResponseBuilder upgrading STOP to tool_calls because of that chunk. Both
  failures have permanent focused regressions. The adapter restores final status
  only for that matching artifact and rejects mixed/duplicate/mismatched artifacts
  and nonterminal/refusal results. The name is reserved at modern profile selection
  and wire preparation, without changing legacy native normalization. Conservative
  input budgeting also has a failed-then-passing schema-byte regression.
- Latest tagged live test passes: six Gemini streamed requests covering short,
  long, silence, native tool submission, acknowledgment and later result. Original
  serialized prefix remains stable. One test passes, three excluded, seed664487
  (message-c-live-provider-latest.log).
  No provider env contents were read directly and no credentials were logged.
  The runner alone loads credentials in its child test process.
- Live complete-object validation observations before TTS: short918.599ms/21 output
  tokens; long1336.114ms/164; silence766.928ms/19; tool acknowledgment656.922ms/25;
  completion829.444ms/27. Inputs1004–1096 tokens; cached input reported zero.
  These are individual observations, not first-audio percentiles. Full buffering
  exceeds the broader one-second voice target for the long response before TTS;
  no incremental framing or latency guarantee is claimed.
- Format, warnings-as-errors compile and strict Credo pass on this increment.
  The root backend run is underway in message-c-root.log; all C/D checkboxes remain
  open pending the complete exits, remaining configured browser/transfer/recovery,
  first-audio and common/Lean evidence. No commits or deployment requested.

### Explicit legacy sample compatibility review

- The first broader run found eleven STS helper regressions from treating its
  existing nil/legacy plan input as a full current plan, and twelve outgoing-call
  fixture startup regressions from a missing protocol-support declaration. A
  ResolvedCallPlan-owned compatibility accessor preserves the former API; explicit
  fixture declarations preserve the latter. Focused STS/diagnostic88/0, seed342061;
  outgoing-call21/0, seed881594. The deterministic diagnostic model now authors the
  selected response contract; external model responses still require strict parsing.
- Stopped that already-failing root run after gathering the distinct regressions.
  No root pass is claimed. A subsequent host-only run passed Console570 tests but
  exposed ten Persistence failures: existing sample/provider/credential scenarios
  create revisions for profiles not in the first modern allowlist.
- Astra xhigh separately reviewed an explicit compatibility decision before its
  implementation. Existing sample owners may choose agent_protocol_version: :legacy
  at creation, persist a versioned bundle and pin shared/summary instructions.
  Normal saves remain modern by default; unsupported modern combinations still
  fail. Dispatch uses stored version, never bundle presence or failed validation.
  Public source/request parameters cannot select this host option. Existing
  revisions cannot be relabeled by publication/preparation/resumption options.
  The reviewer preferred this to altering sample provider/credential coverage or
  omitting prompt pinning. Updated the design/C task explicitly; no new checkpoint.
- Red activation regression: capture(:legacy) was absent in
  message-c-explicit-legacy-red.log. Added fixed version validation/composition and
  activation selection; focused activation3/0, seed857405. Protocol/publication and
  sample/credential owner tests are being verified before the fresh full run.

- Explicit legacy owner checks pass: Calls17/0 seed519133; Persistence sample,
  credential and codec42/0 seed443713. Sample creation persists the legacy version;
  a resumed historical draft explicitly retains that version. Existing metadata
  takes precedence over later creation options. Astra's implementation review of
  this compatibility increment is clean; pure checks3/0 seed94577.
- Astra then validated a third P2: buffered reserved-name calls could masquerade
  as Google streaming artifacts. Permanent req_llm_artifact_test failed first
  (message-c-buffered-artifact-red.log). Normalization now requires explicit
  Google modern-stream context supplied by consume_stream; buffered calls reject
  the reserved shape. Legacy calls remain unchanged. Independent pure re-review
  passes4/0 seed245185 and reports no remaining validated issue in the increment,
  including refused/truncated/mixed/duplicate/non-Google cases. Verification used
  in-memory compilation without writes to the concurrent root run's build.
- The fresh common sequence is session78134. Its format/compile/Credo passed
  before the last adapter-origin fix; root seed964180 has passed AgentRuntime143,
  Call Engine2484 and Calls390 tests. It encountered a Telnyx phone-transfer
  recovery failure: custom_url/destination-loss case waits two seconds for its
  model continuation while outgoing audio/mark messages remain. That scenario
  compiles an inline legacy plan, so no modern reply-format cause is established.
  The root run is still underway; lock/Lean follow only on success. Astra is
  inspecting causality without competing media work. After the run, isolate
  phone_loss:destination at the same seed before changing code or deadlines.
  The post-adapter normal provider/runtime/static/root checks remain required.
  C/D task groups stay open; no full verification or checkpoint C pass is claimed.

- Session78134 finished with5,387 tests, one Gateway failure and386 exclusions;
  all ten apps ran. The isolated same-seed destination-loss case then passed1/0,
  15excluded, in4.7s (message-c-phone-recovery-isolated.log). No cause or production
  repair is claimed. Astra confirms automatic socket-mark acknowledgment and
  identifies the source acknowledgment's admission/synthetic-TTS driving as an
  unproven diagnostic avenue. If the case recurs, inspect bounded coordinator
  current/awaiting-output, room turn speech counters and source TTS request/phase;
  do not log whole private state or simply extend its deadline.
- Post-fix full verification is now session16736, running sequentially with no
  competing media: format, compile, Credo, full Agent Runtime, tagged selected
  Gemini schema/native-tool test, full root seed964180, unused-lock and Lean.
  Logs are message-c-post-{format,compile,credo,runtime,live,root,lock,lean}.log.
  Await completion and fix any reproduced failure; the previous root result is
  not a pass and the final adapter-origin change was made afterward.

- Session16736 completed successfully on the post-artifact source: format,
  warnings-as-errors compilation, strict Credo, full AgentRuntime144/0, tagged
  Gemini schema/tool interoperability1/0, root5,388/0 across all ten applications
  with386 exclusions (seed964180), unused-lock and Lean all pass. The isolated
  phone-loss case and full rerun both passed without a production/test-deadline
  change; its earlier failure remains recorded and unexplained. This is the
  verified C implementation baseline before remaining browser/first-audio and
  profile transfer/recovery acceptance work, not completed checkpoint C.

### Full-allowlist interoperability and profile correction

- The initial real browser host reached Chrome/WebRTC and audible real Deepgram
  output, then looped native calls until model_round_limit. It is a failed
  acceptance run, not a browser pass. The manual harness also let the ordinary
  15-second idle timer fire before controlled input and placed its TTS observer
  in application settings rather than this admission path's per-call
  speech_runtime overrides. The observer therefore missed real synthesis.
  Corrected those test-only settings, preserved/restored prior observer values,
  and started replacing the manual host with an automated agent-browser driver.
- Strengthened the tagged provider matrix to retain its native tool declaration
  for ordinary SHORT/LONG/QUIET and tool ACK/completion requests. The earlier
  passing matrix removed tools for those requests and did not prove configured
  compatibility. The stronger test fails on SHORT: the provider returns a real
  vxpipe_interop_value function call instead of speech. Default, explicit AUTO,
  explicit VALIDATED and stronger command gating reproduce it. NONE yields the
  three dialogue replies but then prevents LOOKUP, so it is not an acceptable fix.
  Reproduction: bin/livetests run --only live_gemini
  apps/vxpipe_agent_runtime/test/integration/req_llm_provider_test.exs:177 against
  the prior Output.object implementation. Logs message-c-tools-{enabled-repro,
  auto-probe,validated-probe,explicit-prompt}.log contain the synthetic scenario.
- Independent Astra xhigh no-network wire inspection passes1/0 seed107986:
  no hidden ANY or synthetic function is sent, and AUTO changes only toolConfig.
  A temporary narrowly scoped decoder trace also captured the raw provider SSE
  functionCall before normalization (message-c-native-sse-probe.log). Removed
  tracing/probe code afterward. No application tool call was normalized away.
  Google's documented VALIDATED default permits direct answers, so the absence
  of toolConfig alone is not a proven cause.
- Astra separately reviewed fixed prompt-guided JSON with strict runtime schema
  enforcement as a coherent replacement candidate for C, conditional on all
  unchanged acceptance gates. Updated the design's concrete profile instead of
  silently falling back after failure. Every modern request now uses text
  generation, including an empty allowlist; canonical publication-pinned dialogue
  instructions require raw JSON with no Markdown/backticks/fences. Runtime strict
  decoding, refusal/terminal validation, bounded complete buffering and admission
  remain unchanged. Legacy replies retain their contract. Removed obsolete Google
  object-artifact acceptance/status restoration and its phantom schema token
  charge; the reserved adapter namespace still fails modern validation.
- Red tests:12tests/3expected failures for unchanged text wire strategy, raw JSON
  prompt guidance and accurate schema-free budget in message-c-text-profile-red.log.
  Focused provider/parser/session/prompt/counter tests now pass30/0 seed819780 in
  message-c-text-profile-green.log. No new malformed-output repair is allowed.
  A raw-text prototype initially returned fenced JSON and failed strict decoding;
  explicit raw/fence instructions fix it without extraction. A separate completion
  observation omitted its literal value; authored acceptance instructions now
  explicitly request that value, retaining the actual-value assertion.
- Current production-boundary tagged matrix passes1/0,3excluded in
  message-c-text-profile-live.log with the full native allowlist throughout.
  Observed complete-validation milliseconds short811.035, long1224.740,
  silence431.495, acknowledgment573.862, completion955.265. Output tokens
  14/148/11/17/21, input1132–1224, cached tokens0. These are individual pre-TTS
  measurements, not first-audio percentiles or proof of the one-second target.
- Added actual buffered provider-boundary coverage for consecutive participant
  inputs after silence, original native calls/signatures/responses and a later
  engine outcome. Strong prefix checks preserve every earlier contents container
  plus the full original final entry's role/fields/serialized parts. Google's
  documented adapter grouping can extend that final entry; no fake assistant
  silence is inserted and no token/cache equivalence is claimed. Prefix lane
  passes5/0 seed309559 (before the additional profile tests). Design now explains
  this provider-normalized content-part guarantee explicitly.
- C's task groups remain open. The first automated browser attempts failed on
  driver locator syntax and then missing async room-preparation wait, before
  any model/media case. Corrected the driver and reran through bin/livetests;
  await the real result. Full profile increment review, browser acceptance,
  transfer/recovery, first-audio comparison and renewed common/Lean gates remain.
- Astra's fixed-profile increment review reproduced two P2 configuration escapes:
  internal operation/object+compiled_schema options could restore constrained
  generation despite Output.text, and tool_choice:required forced ANY forever.
  Added permanent rejection/legacy-preservation tests; the original support
  check failed first in message-c-profile-guards-red.log. Modern support now
  rejects those controls and nonautomatic tool choice before session activation
  or request projection. Generic legacy configuration remains usable. Public
  ProviderSelection already rejects internal controls through its explicit
  common/provider allowlists. Focused provider tests pass9/0 seed71650 in
  message-c-profile-guards-green.log; independent re-review is pending.
- Automated Chrome preparation exposed a readiness race in the harness: it
  clicked Connect as the console mounted, before the RTVI client initialized.
  Failure screenshot showed Client INITIALIZED only afterward, with zero peer
  connections/channels and no model requests. Added an actual initialized-state
  wait before connecting, rather than a fixed sleep. Additional earlier driver
  failures were invalid top-level await syntax, corrected with async expressions.
  No acceptance pass or product-interface fix is claimed from those attempts.
- The initialized-state wait did not resolve the browser connection failure;
  the earlier readiness diagnosis remains a hypothesis, not a proven cause.
  Safe click/path/status capture confirms actual Create room/Connect clicks,
  successful admission/session201 responses, then a Daily media bundle load
  before any captured RTCPeerConnection. Investigating this dependency boundary;
  repeated attempts are not successful browser acceptance or latency evidence.
- Astra found one further P2: accepted output_repair callbacks are incompatible
  with the fixed Output.text descriptor and fail before a provider request.
  Permanent callback case fails9/1 first (message-c-repair-guard-red.log), then
  passes9/0 seed568629 after rejecting the option for modern support. Legacy
  remains usable. Final independent increment review passes3/0 seed334206 in
  vxpipe-review-c-profile-guards-final.log, covering all three reproduced findings,
  duplicate choice options and buffered/streamed text bodies across allowlists.
  Reviewer reports no remaining validated profile/placement issue. This closes
  the increment review, not the whole checkpoint's acceptance or common gates.
- Astra separately reproduced the harness readiness false positive in Node VM
  using the exact source readiness expression and installed SDK Connect handler:
  a historical initialized event leaf makes readiness true while real client
  state is initializing; the handler silently returns with zero connect calls.
  Scoped the wait to the DataList Client dt/dd value. This is a validated harness
  correction; its effect on the actual browser run remains to be tested after
  the running umbrella/Lean sequence. No production media-manager change is justified.
- Renewed fixed-text-profile format, warnings-as-errors compile and strict Credo
  pass; all AgentRuntime147/0,9excluded pass seed321890. Root seed964180,
  unused-lock and Lean run sequentially in session28792 with logs
  message-c-text-{root,lock,lean}.log. No competing provider/media run is active.
  Await the terminal result before claiming renewed full verification. The
  subsequent test-driver selector-only correction still needs final static checks.
- Independent corrected-readiness review passes4/0:
  node --test vxpipe_review_c_browser_readiness_test.cjs. Replaying the original
  defect with VXPIPE_REVIEW_READINESS=historical yields2expected failures.
  Logs vxpipe-review-c-browser-readiness-{green,red}.log. The test extracts the
  actual predicate and installed SDK handler, rejecting historical-only and
  actual-initializing fixtures while permitting the actual initialized Client row.
  Strengthened browser acceptance to require all seven cases, silence without
  output/audio, one native tool completion, later speech and actual HTTP-body
  content-part prefixes, not merely some received audio. Test cleanup now tolerates
  only an already-removed room's noproc race; other cleanup failures remain visible.
- Session28792 finished successfully: all ten applications pass5,391 tests,
  zero failures,387excluded at seed964180; unused-lock and Lean pass. Full runtime
  separately passes147/0. The fixed-text profile core has renewed full backend
  evidence. Selector/assertion/cleanup changes in the tagged browser harness
  still need its real run and final static verification; this is not a C exit.
- The scoped Client-status wait establishes real Chrome/WebRTC connectivity.
  Awaiting bot-ready as well as an open channel fixes an early SHORT admission
  failure before any model request. Response telemetry now captures only selected
  final content/status/usage, excluding context, headers and request options.
  The first observer attempted length(nil) on a legitimate absent native call
  list and detached; corrected the test observer with List.wrap, not provider code.
- An isolated configured call exposed a real model-format issue after prior
  spoken history: LONG returned the exact agent_mode/message plus copied type
  and participant_id fields. The decoder correctly rejected it and emitted no
  LONG speech (message-c-browser-isolated-response.log). Kept all history fields
  and strict parsing. Added canonical pinned guidance distinguishing stored
  records from generated replies, with two-field examples. Prompt test failed
  before the source edit, then Prompt/Protocol6/0 passed seed580564. Strengthened
  the tagged provider matrix with actual Message.spoken_assistant history between
  ordinary and native continuation rounds. Its old-prompt run passed; the log
  named history-contract-red is not failing/red evidence.
- Astra reviewed the guidance change with no new validated contract, trust,
  placement or pinning finding. The subsequent configured browser completed all
  seven dialogue/audio cases (short, long, silence, lookup, unrelated math,
  actual completion, later short) with eight actual Google requests and real
  Deepgram speech. That run failed its tool-event assertion because source
  tool_visibility retained the existing hidden default; no prefix assertion had
  executed yet. Explicitly set full visibility in this synthetic acceptance spec,
  preserving production defaults and the assertion instead of dropping it.
- One replacement browser run was mistakenly started before its predecessor's
  handle was confirmed terminal. Stopped the replacement by its own log file's
  process owners, then confirmed both handles terminal; neither overlapping run
  is timing/acceptance evidence. A later full-visibility attempt also received
  SIGTERM with no ExUnit totals despite outer exit0; it is not a pass. Added
  separate CLI process sessions and globally random browser-session names, then
  cleaned the two orphaned task browser sessions. No cause of that later signal
  is established by these mitigations.
- Critically, the next isolated CLI run still failed LOOKUP's acknowledgment:
  the real final reply copied type/participant_id despite the stronger canonical
  guidance (message-c-browser-isolated-cli.log). Tool visibility worked and
  showed its native function card. This invalidates any reliability claim for
  the current prompt-only Google candidate; do not rerun until a lucky pass and
  declare support. Runtime fails closed as intended. C remains open while the
  provider strategy is reconsidered against the complete unchanged contract.
- Astra reviewed replacing the unverified initial provider with the existing
  direct OpenAI Luna integration as scope-compatible: C requires a verified
  selected profile, not Google specifically. Native text.format avoids reducing
  the response contract or removing attribution/tools. No support selection has
  changed yet. Original legacy Google publications remain separate.
- Added a tagged OpenAI capability prototype that retains actual attributed
  assistant history and the full native tool declaration on every round. It
  checks the actual streamed Responses text.format strict schema rather than
  relying on ReqLLM's Output.object, whose automatic mode would force a synthetic
  structured_output function with business tools. Prototype sends the native
  response_format option with Output.text so original returned text still goes
  through Dialogue.decode; no repair or synthetic-function normalization.
- Initial prototype proved strict schema/full-tool wire but failed an extra
  parallel_tool_calls:false assertion. The installed Responses stream encoder
  omits supported openai_parallel_tool_calls; direct parallel_tool_calls is
  rejected by its options schema. This flag is not a C requirement; current
  Responses docs and source treat text.format independently. Kept the API's
  parallel default and existing runtime call bounds, full tools and strict schema
  assertions. Astra separately confirms this preserves scope. No body-rewrite
  callback or reduced native allowlist was introduced.
- OpenAI capability prototype now passes eight real streamed requests,1/0 in
  25.7s (message-c-openai-strict-native.log): short, long, silence, actual native
  lookup, acknowledgment, unrelated math, actual-value completion and later
  short. Individual full-validation ms4705/2875/1315/2425/3120/1923/1931; reported
  reasoning tokens vary0–69. These are not first-audio measurements or accepted
  voice latency. Reasoning token counts alone do not establish returned opaque
  item presence; the live prototype must inspect counts without logging contents.
- Astra reproduced a real blocker with a populated returned reasoning item:
  normalization -> retained Message.assistant -> projection loses it while direct
  SDK replay retains it. Scratch vxpipe_review_c_openai_reasoning_replay_test.exs
  fails one assertion, seed501365. Also reproduced why raw SDK metadata copying
  is unsafe: phase_items resurrects redacted canonical text and responses_replay
  resurrects removed canonical calls (vxpipe_review_c_replay_shadow_test.exs,
  two expected failures, seed167759). These are design counterexamples to a raw
  snapshot, not defects in an already implemented provider_replay field.
- Required next work is a bounded, versioned private replay field with provider/
  model scope, digest binding to canonical text/calls, exact opaque reasoning
  and phase/layout references. Runtime owns bounds/lifecycle; adapter owns native
  format/reconstruction. Do not copy alternate text/arguments in raw metadata,
  weaken telemetry redaction, remove native attribution, skip replay evidence,
  or enable the OpenAI profile before the complete C gates pass. The milestone
  still has13open groups; D has not started. No commits or model artifacts.
- Added bounded private replay lifecycle after focused red4/8 failures,
  seed865416. ModelResponse/Message carry a string-key JSON map, 64 KiB serialized
  limit and finite depth; malformed values reject without truncation. RequestRunner
  retains it on original native exchanges and generated-history finals, while
  spoken/initial history rejects injection. Nonempty replay contributes to the
  conservative input budget; semantic compaction excludes it and protected native
  groups retain it unchanged. Focused lifecycle/compaction16/0 seed163549. Astra's
  independent boundary/depth/privacy/protected-pair scratch checks3/0 seed700057;
  no validated generic lifecycle issue. The first green attempt exposed an
  assertion expecting a private validation atom rather than SessionConfiguration's
  existing public invalid_configuration result; corrected the test expectation.
- Added adapter-owned OpenAIReplay with versioned provider/model scope, digest
  binding to canonical text/calls, ordered reasoning items and one supported phase.
  Never copy alternate text/arguments through raw SDK snapshots. Unknown shadow
  replay, multiple phases and unsupported content layouts reject before side
  effects. Buffered and streamed fixtures plus a real runtime-session continuation
  preserve nonempty synthetic opaque replay, call IDs and result pairing.
  Adapter red3/3 seed227746; initial fixture used the dependency's tool_call helper
  with string arguments, corrected to its required map form; focused green11/0
  seed734403. Replay stays out of ordinary content, inspection, compactor semantics
  and telemetry. Final host-settled dialogue deliberately does not attach generated
  reasoning to supported spoken text; Astra reviewed this as consistent with the
  next request starting from truthful speech and preserved native facts.
- Astra reproduced loss of streamed text-part phases and acceptance of multiple
  phases (scratch2failures seed574087). Permanent red1failure seed53583. Capture
  now checks both message and text-part phase metadata, preserving a supported
  single phase and rejecting inconsistent/multiple phases. Original Astra
  reproduction independently green2/0 seed73621. SDK strips text output_index;
  same-phase chunks are supported as one canonical text, not a claimed retained
  multi-phase layout.
- Strengthened OpenAI live prototype to compare actual next-wire reasoning items
  and report only counts/hashes. An initial authored instruction ambiguously
  elicited a listener acknowledgment; explicit main-response instructions fixed
  the scenario without weakening format or mode assertions. Eight real requests
  pass1/0 in18.8s. Native lookup returned zero reasoning items: equality of empty
  live replay is not evidence of nonempty live replay. Other final replies did
  return reasoning; positive native preservation is established by fixtures.
- Selected the OpenAI Luna native strict Responses strategy in the C implementation,
  excluding both failed modern Google candidates while preserving legacy profiles.
  Modern requests project native response_format into actual text.format with
  Output.text, keeping strict runtime decoding, no repair and the full native
  tool allowlist in every round. No round-dependent strategy or synthetic function.
  Schema input cost is counted again. Guard tests and actual buffered wire tests
  red3failures, then combined focused38/0 seed451804.
- Promoted the tagged test from manually bypassed prototype options to actual
  Provider.stream with modern protocol. Eight submitted requests pass unchanged
  strict schema/tools and exact input-item prefix checks,1/0 in18.9s, seed179351
  (message-c-openai-profile-live.log). Reported cached input1239–1539 tokens in
  later requests; this is observed provider accounting, not a cache guarantee.
- Real Chrome acceptance now uses the actual UI textbox/SDK, OpenAI profile,
  published modern revision, actual admission/RTC and real Deepgram TTS. All seven
  cases and eight provider requests pass1/0 in62.6s (message-c-openai-browser.log):
  Ready, long reply, valid silence with zero audio, native background lookup,
  Checking, unrelated Four, actual completion and later Ready. Exactly one native
  tool start/completion,1556 inbound audio packets and1405 non-silent frames. Full
  schema/tools and submitted prefix assertions execute. First-audio individual
  ms2559.6/4412.2/(silent)/4459.8/4882.2/3424.4/2073. These exceed the unchanged
  one-second voice target; no percentile or complete C acceptance is claimed.
  Desktop inspected with correct human/assistant entries and no control JSON.
  Phone capture remained on its audio tab despite the initial click selector;
  changed driver to wait for the visible outer mobile conversation tab and visible
  composer before screenshot. That new phone inspection is still pending.
- Astra reproduced exact-profile guard gaps with alternate provider_model_id and
  conflicting atom/string wire metadata (scratch2failures seed17460). Permanent
  guard red1failure seed554442, and replay-scope red
  seed367603. Extracted cohesive DialogueProfile owner; it binds support/replay to
  the effective provider model and ReqLLM's resolved API route. Legacy requests
  cannot replay opaque data into a different effective model or API route.
  Corrected an over-specific test expecting absent extra metadata to be rejected:
  ReqLLM legitimately resolves this known model to Responses without that hint.
  Combined profile/replay/history green19/0 seed340301. Final Astra re-review,
  recovery acceptance, phone inspection and renewed common gates remain pending.
  A/B stay complete; C8/D5 remain open. No commits or model artifacts.
- Final increment Astra re-review has no remaining reproduced defect or ownership/
  dependency finding. Independent profile binding, legacy replay scope and phase
  checks5/0 seed272137 (vxpipe-review-c-openai-binding-phase-green.log).
  Full AgentRuntime157/0,10excluded seed810861; root format, warnings-as-errors
  compile and strict Credo pass. Current root/lock/Lean sequence is still running.
  Explicit C acceptance gaps are a modern configured transfer retaining pinned
  destination prompt/decoder after prompt edits, recovery followed by a valid
  response, phone conversation inspection and the complete checkpoint review.
  These are evidence gaps rather than reproduced implementation bugs. The phone
  driver now uses a real pointer click for the Radix tab and waits for its visible
  composer; the earlier DOM click left the audio tab selected in its screenshot.
- Renewed umbrella run seed260476 exposed two assertion false positives in the
  structured ToolConversationRoom/TextToSpeechTurn cases: broad content substring
  searches also inspected the newly documented silence example in the system
  prompt. Scoped both assertions to assistant history while retaining the ban on
  fictional silence entries. The currently running umbrella command still
  reports that pre-fix result; focused re-verification and the subsequent full
  passing run are required. It has not yet reached its final umbrella totals, so
  lock/Lean steps have not run. Do not claim this gate sequence passes.
- Removed the rejected modern Gemini live probe and its exclusively used helpers;
  OpenAI's actual selected-profile test now owns that schema/tools/history lane.
  Existing legacy Gemini native tool/session interoperability remains intact, and
  modern Google rejection has permanent no-network coverage. This removes an
  obsolete success expectation rather than accepting the rejected provider.
  Formatting, JavaScript syntax and whitespace checks pass; current source has no
  commits. C and D remain open.
- The pre-fix umbrella run finished all ten apps with13failures total: the two
  broad silence assertions plus11 publication fixtures that expected modern
  Google support (seven Persistence, four Console). All other tests passed.
  Updated provider-agnostic inherited-service authorization coverage to the
  selected OpenAI profile. Explicitly pinned existing Google credential/transport
  and carrier fixtures to legacy, preserving their intended provider/prose lane.
  Added a persisted normal-authoring regression proving Google modern validation
  rejects publication without fallback and OpenAI modern metadata survives save,
  publication and preparation. This keeps default modern coverage separate from
  deliberately preserved legacy compatibility; production defaults are unchanged.
- Focused repair runs all pass: two selected room/TTS tests; complete InlineTenantVoice
  and ConfiguredSamples files; and the existing Console telephony file's default
  lane. Renewed common gates are required after these verified fixture corrections.
- Renewed baseline common gates all pass: format, warnings-as-errors compile,
  strict Credo, root5,402tests/0failures/387excluded seed438097, unused-lock and
  Lean (message-c-profile-final-* logs). The subsequently added modern transfer
  acceptance case had not been loaded by that run's Call Engine test process.
- Added configured modern transfer + failed-reply recovery + supervised Session
  restart coverage in AgentTransferRoomTest. It captures packaged prompt files in
  a temporary directory, edits their source after capture, transfers with the
  original bundle, rejects destination prose, speaks a valid structured reply,
  terminates/restarts the Session through its owning supervisor, then verifies
  unchanged pinned instructions/decoder and another TTS/audio settlement.
  This is supervised Session restart evidence, not automatic whole-graph crash
  recovery. Existing supervision tests retain that separate responsibility.
- First acceptance run failed because its new sink helper matched an earlier
  empty failed turn's finish notification. Scoped frame/finish acknowledgments
  to the exact output correlation; no production change was needed. Focused
  transfer/restart case then passes1/0,13excluded seed839569
  (message-c-modern-transfer-scoped.log). Broader file verification is pending.
- Astra's complete C source audit has no validated remaining defect or SRP/
  dependency issue. Independent parser/protocol/replay22/0 seed27313 and actual
  selected-profile dynamic-context wire exception1/0 seed109871. The latter
  changes only the transient system projection, preserving native history and
  schema/tools/rest of the submitted body. Final evidence review remains pending
  the new transfer case's broader run, phone view and current completion records.
- Astra found the first prompt-pinning test used the same initial text as packaged
  defaults, so it could not distinguish accidental source reload. Its pure
  discrimination reproduction failed1/1 seed214242. Added a unique marker before
  capture and replaced it afterward, proving captured/package/edited values differ.
  The complete transfer file passes14/0 seed970070; independent marker check1/0
  seed807381. No production bug was found or changed for this evidence correction.
- Phone driver attempts completed actual dialogue but failed inspection for
  different harness reasons: DOM click did not select the panel, a CLI selector
  with :visible failed lookup, and a tagged tab click still did not activate it.
  The accepted driver locates the visible outer conversation tab using its actual
  aria-controls target, focuses it and presses Enter, then requires a visible
  composer. No product UI behavior was changed. One separate run timed out in
  Runtime.evaluate during long audio: its awaited JS promise could outlive the
  browser command's CDP timeout. Replaced that long promise with the CLI's supported
  wait --fn synchronous polling, retaining the complete long speech case and audio
  quiet/stop assertions instead of reducing the scenario.
- Final configured browser run passes1/0 in62.5s
  (message-c-openai-browser-phone-poll.log): eight actual OpenAI requests, unchanged
  strict schema/full tools/input prefixes, seven cases, one tool start/completion,
 1532 received audio packets and1633 non-silent frames. QUIET has zero output/audio.
  Inspected desktop1360x900 and phone390x844 conversation screenshots: human and
  assistant speech are readable, control JSON absent, silence creates no false
  assistant bubble, and the phone composer is visible. The screenshots belong to
  the task session ba781d597e51fa73; failed inspection runs remain separate evidence.
- Recorded per-round complete-provider durations, input/output/cache tokens and
  first-audio samples in the design. First audio1.986–4.993s exceeds the unchanged
  voice target; this is not a percentile or controlled legacy comparison. Reported
  cache input1176–1765 tokens is actual accounting, not a guaranteed hit. Catalog
  pricing is unknown, so no monetary cost is invented. Final current-source C
  gates are running before checklist completion.
- D implementation direction (not implemented): Room owns the scoped hold/timer/
  acknowledgment and stale-output guards; Coordinator owns scheduling and existing
  completion leases. Prefer a bounded durable engine-observation append that does
  not generate speech: hold-time background outcomes and early cancellation stay
  factual context, while actual idle completion followed by typed idle_timeout
  triggers exactly one model continuation. This preserves original completion
  payloads and avoids adding a batch envelope or pending-status snapshot to model
  history. Existing authorized workers execute the native idle tool. Red tests
  must cover retention/idempotency, quiet-period suppression, cancellation and
  lease/notification ordering before production changes. This planning adds no
  D task completion or new external message fields.
- Prepared the first D runtime contract as standalone scratch tests while C's
  current-source umbrella command remains active. Four tests require bounded,
  durable, idempotent engine-observation retention without generation, exact opaque
  text/native outcome preservation, a following single typed timeout continuation,
  and refusal during generation or outstanding host settlement. Caller-origin,
  oversized/invalid UTF-8 and absent correlation inputs must reject. After fixing
  the scratch setup to include the modern protocol's required pending-context
  source, all four fail for the intended missing Session.record_engine API,
  seed573338 (message-d-engine-observation-red-focused.log). The earlier scratch
  startup failures were harness errors, not feature-red evidence. Tests remain
  outside the repository until the C checkpoint is closed; no D runtime behavior
  or task completion is claimed.
- Checkpoint C is complete. Current-source root5,403tests/0failures/387excluded
  seed918318 passes with format, warnings-as-errors compile, strict Credo,
  unused-lock and Lean (message-c-checkpoint-* logs). All eight C groups are now
  checked; A10/B7/C8 are complete and D5 remain open. The index remains unchecked.
  Final Astra source/evidence reviews have no validated remaining defect or owner
  issue. Browser1/0 seed853195, transfer/restart14/0 seed970070 and independent
  runtime/dynamic-prefix/prompt-discrimination evidence are recorded above.
  Updated design and index with accepted support and measured limits; no classifier,
  word timing or audible listening-cue implementation is claimed. No commits.
- Closed C's final documentation review correction: the linked storage/viewer
  design now reflects A/B/C complete and D pending. Astra confirms status/evidence
  synchronization and zero remaining C findings.
- Started D with the durable engine-observation Session boundary. Copied the four
  prototype tests into the owning AgentRuntime app; native focused red4/4 missing
  API failures seed589669. Added Session.record_engine with nonempty correlation,
  existing bounded engine-input validation, UTF-8/nonblank validation, durable
  idempotent append and busy refusal during generation or pending host settlement.
  It neither generates a model request nor wraps/rewrites completion text. Focused
  green4/0 seed649667. Broader runtime and independent review pending. Native idle,
  room hold/timers, coalescing/admission and D acceptance are still unimplemented;
  all five D task groups remain open.

- 2026-11-17 D progress: full AgentRuntime suite after record_engine passes
  161/0,9excluded seed752799 (message-d-engine-observation-runtime.log).
  Independent Session retention/compaction/input checks6/0 seed660670; no remaining
  validated API finding. Stable activation/invocation keys are used by the new
  Coordinator consumer, rather than regenerated continuation correlations.
- Added InvocationRegistry.running_execution and a conservative monotonic deadline
  to canonical records. Native red9tests/3missing-API failures seed0, green9/0
  (message-d-running-execution-{red,green}.log). Running/unexpired canonical
  context, handler, arguments, worker and completion target can be checked before
  lifecycle events arrive. Terminal/leased/consumed/expired records cannot authorize
  control. Independent Astra10/0 includes immediate worker lookup with lifecycle
  delivery disabled; no validated defect or ownership finding.
- Native Idle/Request now expose exactly integer duration_seconds1..300. Platform
  aliases default to non_blocking and reject explicit/direct blocking bindings.
  InvocationConfig extends only actual platform Idle calls by their quiet duration
  plus30s arming and5s grace; worker timer and record deadline share that effective
  budget. Unit red5/5, combined green14/0 seed933675
  (message-d-native-idle-{red,green}.log). Independent Astra16/0 also verifies an
  actual aliased worker budget; no remaining boundary finding.
- Connected the first Room IdleWait and Coordinator IdlePause path. The room holds
  the native worker reply while continuing callbacks, owns acknowledgment-relative
  timers and permits only associated output. Coordinator durably retains genuine
  outcomes without generation, then admits one typed timeout after idle completion.
  Existing native call/ack/completion formats remain unchanged. Extracted shared
  IdleNotification construction from ordinary CallerIdle. A first timer callback
  pipe passed arguments in the wrong order; the focused test caught the Room crash,
  and the corrected call passes (message-d-idle-control-green.log,1/0 seed632485).
- A deterministic early-resumption test suspends the invocation worker after the
  silent acknowledgment. It reproduced fresh input reaching the model before the
  actual cancellation completion (message-d-idle-resumption-red.log,3tests/1failure
  seed0). Coordinator now queues that input until the genuine completion is
  retained, without blocking Room input admission. Green3/0 seed0.
- Failed acknowledgment red reproduced an expired result and unwanted timeout
  generation (message-d-idle-ack-failure-red.log). Room now cancels that exact
  acknowledgment hold on generation failure. Current configured Room suite4/0
  seed0,15.1s (message-d-idle-control-four-green.log): held spoken acknowledgment,
  real ten-second silent wait, early resumption with completion-before-input, and
  failed acknowledgment with no timeout generation. These are fixtures, not live
  provider/browser acceptance. No D task is checked off.
- Current root Credo flags RoomAuthority at824lines exceeding its800line ownership
  limit (message-d-idle-control-credo.log). Extract a cohesive existing callback/API
  responsibility; do not suppress or raise the check. Full D source review is
  requested from Astra and is in progress. Remaining known work includes older-
  output exact-target cancellation (current admission rejects multiple active room
  turns), unsupported legacy/STS publication guards, broader source/sink/race and
  background completion cases, real browser acceptance and renewed full gates.
  Whole milestone/index remain unchecked; A/B/C evidence stays historical.
- Extracted unchanged startup media binding/registration helpers into
  RoomAuthority.MediaBindings, leaving RoomAuthority782lines below the800line
  limit. Formatting and whitespace checks pass; renewed Credo/compile/runtime
  verification is pending the reviewer's reserved configured-room test window.
  Astra is constructing a deterministic late-arm test: hold Room while native
  submission and acknowledgment generation finish, then resume Room with the
  Coordinator already awaiting output. No finding is claimed before reproduction.
- Added a publication guard for native idle: a pinned modern LLM participant
  is required; nil/legacy protocols and speech-to-speech cannot advertise this
  operation. A focused profile regression first failed because legacy pinning
  accepted idle (vxpipe-d-idle-profile-red.log,6tests/1failure). The guard lives
  in AgentProtocol alongside profile validation; modern fixture publication
  remains accepted. Direct activation bypass checks and full publication path
  acceptance remain pending; this does not complete D's availability group.
- Astra reproduced late Room idle admission after acknowledgment generation:
  Coordinator current was nil, awaiting_output retained the origin, and arm ignored
  it. The next request incorrectly contained only the expired tool observation.
  Permanent configured regression added; repository red5tests/2failures seed0
  also reproduced the same race in the original happy path. IdlePause now accepts
  the exact current or awaiting-output correlation, preserving Room authority.
- Direct RuntimeGraph legacy-idle activation regression red4tests/1failure; added
  a defense before tool compilation. Publication and activation both require the
  modern protocol for native idle. Broader D gates and final review remain open.
- Late-arm and activation combined suite passes9/0 seed0
  (vxpipe-d-late-arm-green.log). Independent Astra original reproduction plus
  activation/profile/boundary checks11/0 seed0 confirms the fix and cohesive
  ownership, with no remaining validated finding in that increment.
- Added configured background-tool completion during idle quiet. The controlled
  native host tool returns while the hold is active; its actual original-format
  result appends without a model request or TTS, and expiry produces one typed
  idle_timeout after both actual completions. Focused test passes1/0,5excluded
  seed820099 (vxpipe-d-idle-background.log). No production change was needed.
  TestTurnCall now accepts an explicit host registry for this controlled fixture.
  D remains open; this is fixture coverage, not browser/provider acceptance.
- Renewed strict Credo passes after MediaBindings extraction
  (vxpipe-d-idle-credo-current.log). Existing Coordinator, tool-conversation,
  call-lifecycle and idle room regression set61/0 seed599380
  (vxpipe-d-idle-regression.log). Added idle worker-loss case1/0 seed868125:
  supervised worker termination retires the quiet timer; its actual failed
  completion is retained and new human input proceeds without timeout speech
  (vxpipe-d-idle-worker-loss.log).
- User asked whether speech-to-speech agents are considered. Confirmed the
  approved LLM-only idle/dialogue scope and shared/native STS compatibility.
  Added direct STS startup regression: without publication validation, the
  new catalog entry could still be advertised through native tool preparation.
  Red13tests/1failure (vxpipe-d-sts-idle-red.log); SpeechToSpeechActivation now
  rejects native idle in resolve and deferred remote registry construction.
  Existing STS prompt/provider configuration contracts remain covered by the
  full same-file suite. D's exact-target cancellation and full acceptance remain
  pending; no milestone task has been marked complete.
- Began scoped TTS cancellation API accepting exact TextToSpeechRequest targets.
  Tests cover obsolete generation no-op, selected queued removal while current
  and unrelated pending speech survive, and current cancellation retaining queued
  replacement until provider terminal. Initial suite red12/2 missing API. First
  green attempt exposed the fixture queue limit1; test now explicitly requests2
  slots for its two pending requests. Room idle target selection/integration is
  still pending; this API alone does not complete exact-target idle cancellation.
- Scoped TTS suite green12/0 seed234525. Broader TTS capability/room and
  cancellation/order/deadline regression27/0 seed152089. Added repeated scoped
  cancellation while provider terminal is pending: unavailable leaves retained
  speech untouched; obsolete-generation retry is a no-op. Renewed focused12/0
  seed372648 (vxpipe-d-scoped-tts-reentrant.log). Existing Lean lane passes
  (vxpipe-d-scoped-tts-lean.log); it is existing model/replay coverage, not a claim
  the new scoped-target API itself is formally modeled. Whitespace check passes.
  An initial formatting command used root-relative paths from the child directory
  and found no files; rerun with child-relative paths succeeded. No source was
  changed by that failed formatting attempt. Room-level integration remains open.
- Independent Astra scoped TTS review13/0 seed0 found no validated defect;
  output cancellation remains owned by TTS. Added TurnState exact speech request
  retention and matching once-only settlement to prepare Room target selection.
  Red3tests/1missingAPI failure; room mode/TTS/idle suite14/0 seed430518
  (vxpipe-d-speech-targets-green.log). Pending counts now derive from retained
  requests; stale generation/duplicate completion cannot decrement another output.
  A subsequent playback authorization guard checks retained request membership
  before archive/history updates; its focused TTS verification is running.
  The exact idle target selection/cancellation integration is still pending.
- Added room idle target selection and retirement: only older admitted output
  with completed generation is eligible; newer/unfinished concurrent turns reject
  stale idle. AgentOutput uses retained exact TTS requests and removes only the
  selected old turns, without cancelling the current idle acknowledgment model
  request. Focused selection and retirement tests each first fail for missing API.
- Combined room/idle verification currently11tests/1failure seed621670
  (vxpipe-d-idle-retire-green.log): late-arm reproduction immediately inspected the
  suspended Room mailbox before the invocation worker had necessarily sent its
  request. That setup assertion is a test synchronization race, not evidence of
  production behavior. Asked Astra to review integration and a deterministic
  synchronization correction. Do not claim this increment green or D complete.
- Fixed late-arm harness synchronization with send tracing on the actual
  native invocation task before inspecting the suspended Room mailbox. If the
  idle request is not already queued, await its traced GenServer call; no sleeps.
  Re-ran the failing seed621670: room target/idle11/0 in18.7s
  (vxpipe-d-idle-retire-recheck.log). Astra confirms the synchronization covers
  all before/during/after-trace orderings; integration source review is ongoing.
- Early human resumption before acknowledgment generation passes1/0 seed977845
  (vxpipe-d-armed-resumption.log): old provider task terminates, actual cancelled
  result precedes new input, and stale acknowledgment cannot produce TTS/timeout.
- Full CallEngine child suite is running as session76669, log
  vxpipe-d-call-engine-current.log, seed55168; it predates the following fix.
  Astra reproduced a played-time overwrite in scoped interruption: current500ms
  followed by queued0ms from the same turn emitted0ms. Scratch red1/1 seed0 at
  vxpipe-review-d-idle-played.log. Added permanent IdlePlayedTest and scoped
  reply fixture; changed both scoped and existing broad interruption to share
  per-turn summed playback accounting. New focused verification/formatting is
  pending the existing child suite's terminal result. No D completion claimed.
- Permanent played-time reproduction passes1/0 seed0 using a standalone
  source-compiled runner while the child suite retains its test lane
  (vxpipe-d-idle-played-fixed.log). Shared sum fixes both scoped/broad aggregation.
  Files formatted with Code.format_file! without starting a concurrent Mix build.
  Astra re-review requested. Child suite76669 remains live, no terminal result
  or failure summary yet; continue polling the same handle, do not replace it.
- Astra independently verifies played-time fix2/0 seed0, original reproduction
  plus isolation between turns (vxpipe-review-d-idle-played-fixed.log), no remaining
  validated finding in that increment. Browser evidence probe now retains a
  timestamped speech/tool timeline for upcoming idle acceptance; node syntax check
  passes, but no new browser acceptance is claimed. Full child suite76669 is
  still active and emitting progress; continue same handle.

- Full CallEngine run76669 finished: 2508 tests, one failure,100 excluded,
  seed55168 (vxpipe-d-call-engine-current.log). Failure was the discarded-speech
  synthetic fixture setting pending_speech without registering its exact request.
  Updated fixture to TurnState.begin_speech; production authorization remains exact.
  Native focused AgentOutput/IdlePlayed tests pass3/0 seed439863
  (vxpipe-d-discarded-recheck.log). Astra lifecycle/ownership re-review requested.
- Extended existing real Chrome acceptance with native idle spoken and silent
  acknowledgments, each using duration_seconds10, followed by one typed timeout.
  Probe retains speech/tool timestamps; assertions check two timeout requests,
  silence for null responses, and at least9800ms from acknowledgment completion
  to follow-up output. Live run37997 is active via bin/livetests, log
  vxpipe-d-idle-browser.log. This is pending evidence, not completed D acceptance.
- Live browser37997 completed14 model rounds and both idle scenarios, but
  acceptance failed1/1 because the model returned listener/null for the existing
  LOOKUP acknowledgment instead of the requested Checking. No runtime failure
  was inferred from that model choice. Explicitly clarified the test instruction
  for the native running acknowledgment; retained the original speech assertion.
  Idle expiry timestamps were10006.8ms(spoken) and9999.7ms(silent) after settled
  acknowledgments. Strengthened assertions to measure tool expiry itself, then
  require follow-up output after expiry, rather than using LLM response delay
  as evidence of quiet duration. Inspected desktop and phone screenshots
  vxpipe-structured-d60ab8f8934691bd-{desktop,phone}.png: visible speech and
  native tools render without JSON. Second live run started with log
  vxpipe-d-idle-browser-recheck.log; D remains incomplete.
- Astra confirms discarded-speech fixture correction preserves test intent.
  Discarded optional acknowledgment may settle into quiet; this differs from
  failed generation but does not violate optional acknowledgment behavior.
  Further review of invalidation and race handling remains active.
- Second real browser run53011 passes1/0,14 model rounds
  (vxpipe-d-idle-browser-recheck.log). Actual idle tool expiry follows settled
  acknowledgment by10006.8ms(spoken) and10001.2ms(silent). Both desktop and phone
  screenshots inspected: vxpipe-structured-c495faf0fc6e3d01-{desktop,phone}.png.
  This covers acknowledgment/silence and native protocol/prefix assertions, not
  all D configured-call acceptance scenarios.
- Added permanent duplicate-idle model-response test: two native submissions
  yield one failed and one expired outcome, both retained, and only one timeout
  continuation. Pass1/0 seed233604 (vxpipe-d-duplicate-idle.log). No runtime change
  needed for this existing behavior. Added missing-acknowledgment deadline case,
  not yet run. Astra owns the Mix lane for expiry/input race and source departure
  reproductions; do not start competing Mix until it releases the lane.
- Astra validated participant-departure bug2tests/1failure seed0
  (vxpipe-review-d-idle-invalidation.log): removing the actual caller participant
  leaves a draining connection present, allowing idle to expire after source
  authority is gone. Permanent copied case reproduces1/1seed0
  (vxpipe-d-source-departure-red.log). IdleWait admission and reconciliation now
  require source membership in participant_ids, so normal participant lifecycle
  reconciliation retires the wait. No transport-owner change is needed.
- Also retained Astra expiry-before-input test permanently: delayed actual idle
  completion is recorded before fresh human input, with no stale timeout request.
  Full12-case idle suite45847 is running seed0, including missing acknowledgment
  actual30s bound and duplicate calls, log vxpipe-d-idle-invalidation-green.log.
  Independent re-review requested; D acceptance and broad gates remain open.
- Idle suite45847 is terminal green12/0seed0 in56.5s
  (vxpipe-d-idle-invalidation-green.log), including actual30s acknowledgment
  deadline, source departure, duplicate calls and expiry/input ordering. Astra
  has the test lane for independent re-verification. D remains open for broader
  configured-call acceptance, sink/old-output cases and final umbrella/Lean gates.
- Astra independently reverified source-presence fix and expiry/input ordering:
  2/0seed0, vxpipe-review-d-idle-invalidation-fixed.log, no remaining validated
  finding for that fix.
- Added configured almost-finished-answer acceptance: one second of real PCM,
  990ms playback, human stop/wait, exact interruption and native idle, associated
  acknowledgment, stale old completion rejected, then playback-relative timeout.
  Initial fixture used only4bytes with990ms playback, correctly rejected as
  invalid_playback (vxpipe-d-nearly-finished.log); corrected to48000 samples.
  Pass1/0seed872898 (vxpipe-d-nearly-finished-recheck.log); child recheck1/0
  seed891436. This uses current host admission; speculative overlap stays deferred.
- Added failed and stalled acknowledgment sink-finish cases with the real30s
  arming bound. Run93572 currently active, vxpipe-d-sink-bound.log; two cases
  selected at line585. Acceptance review requested, no production change yet.
- Sink failed/stalled finish run93572 terminal2/0 in63.3s
  (vxpipe-d-sink-bound.log). Both retire idle through the actual30s arming bound
  without an independent timeout model request. Provider/sink failure logs are
  expected in these fault cases.
- Ordinary-idle coexistence passes1/0seed608298
  (vxpipe-d-ordinary-idle.log): configured500ms ordinary idle stays suspended
  during explicit1s quiet and its unresolved timeout response, then rebases after
  settled response. Independent review requested for these acceptance cases.
  Remaining D evidence includes teardown/replacement, actual scoped Room/TTS
  boundary coverage, broader configured-call scenarios and final gates.
- Added actual Room/TTS boundary acceptance IdleScopedCancellationTest: old
  current speech is cancelled through real TTS supervision/native cancellation,
  queued origin acknowledgment survives and starts after provider terminal; a
  newer Room turn rejects stale idle before cancellation. Pass2/0seed498957
  (vxpipe-d-room-scoped.log).
- Configured connection replacement passes1/0seed122845
  (vxpipe-d-connection-replacement.log): authorized detach retires idle, old
  connection process terminates, new process reuses the connection ID, stale
  deadline does nothing, and fresh input contains the real cancellation fact.
  Astra owns independent review/verification next; all milestone D boxes remain
  open pending full requirement audit and final umbrella/Lean gates.
- Independent scoped Room/TTS and connection replacement review verification
  passes3/0seed0 (vxpipe-review-d-scoped-replacement.log); reviewer full D
  requirements/ownership audit remains pending.
- Started final sequential root gate run65684: format, warning-free compile,
  strict Credo, full umbrella tests, unused-lock check, Lean. Logs are
  vxpipe-d-final-{format,compile,credo,test,unused,lean}.log. The runner
  stops at first failure; later files/results do not exist until those checks
  actually run. Do not claim gates complete from invocation alone.
- Gate run65684 stopped at formatting: three extra EOF blank lines and one
  unformatted CallInvocation.new call in idle_test.exs. Ran mix format on the
  four reported files only; restarted sequential gates as45076 using the same
  final log names. No runtime behavior changed in this correction.
- Root gate45076 has passed format, compile warnings-as-errors and strict
  Credo. Full umbrella tests are still active, seed515061; do not launch another
  Mix lane. Final audit identified transfer-hold invalidation as needing explicit
  review: ParticipantTransfer.begin holds callers, while IdleWait.deadline
  currently acts before subsequent reconciliation. Astra asked to reproduce any
  defect and distinguish it from source/connection replacement already covered.
  No completion claim or checklist update while this remains unresolved.
- Final audit found transfer-hold invalidation defect. Astra source-compiled
  owner reproduction2/2 failures seed0 (vxpipe-review-d-idle-hold.log): held
  source stayed quiet and deadline published expiry before later reconciliation.
  Retained permanent IdleHoldTest; IdleWait now excludes held sources and
  revalidates at deadline before side effects. Room transfer admission reconciles
  its returned state immediately, retiring idle when transfer holds the caller.
  Original source-compiled reproduction now2/0seed0
  (vxpipe-d-idle-hold-fixed.log). Independent review and configured transfer
  reproduction requested. Root45076 still live and predates this runtime fix;
  its results alone cannot validate the final implementation.
- Reviewer confirms adversarial cases may use real configured deterministic
  calls; the D wording does not require every race to use live providers. Live
  browser10s spoken/silent with native history and desktop/phone inspection plus
  configured cases cover that acceptance scope. No scope reduction was made.
- Astra independently reverified held-source/deadline source reproduction2/0
  (vxpipe-review-d-idle-hold-fixed.log). Configured blocked-destination transfer
  regression is being prepared without competing with root45076.
- Added successive-idle regression source: fresh human input cancels first wait,
  a distinct native call arms second wait, old token is ignored and cancellation/
  expiry are each retained once. Not run yet. Formatted the hold fix and added
  tests with Code.format_file! while root test lane remains active.
- Root45076 progressed: CallEngine2520/0(100excluded) before latest hold fix;
  Calls390/2 exposed obsolete EditorToolCatalog exact lists omitting new native
  idle. Updated both expected built-in lists to include idle; no production
  catalog change needed. Full runner is still active in Gateway and will stop
  before subsequent gates because test command has failures. Focused catalog
  verification pending lane release.
- Integrated configured blocked-destination transfer case into existing
  agent_transfer_room_test.exs with optional reception_tools fixture input,
  preserving other tests' tool configuration. Native run pending root45076
  terminal; also queued successive-idle and editor catalog corrections.
- Astra full D audit maps all five task groups to implementation/evidence;
  transfer-hold configured verification and final gates are the outstanding
  items. Ownership review finds Room/Coordinator/Session/invocation/TTS split
  coherent, with no additional validated defect. Independently inspected both
  accepted D browser screenshots; rendering agrees with recorded timeline.
- Root45076 Gateway887/1(17excluded): five-participant handoff test at
  human_transfer_webrtc_test.exs485 timed out awaiting native_gate_waiting
  adoption_pause after2000ms (final-test.log28816). This run compiled before
  latest hold fix. Do not classify it as unrelated/flaky without reproduction;
  exactseed515061 isolated rerun queued after rootterminal. Reviewer asked for
  read-only causal inspection while lane remains owned.
- Root45076 terminal:5442 tests,3failures,387excluded seed515061.
  Failures: two obsolete editor tool catalog expectations (corrected), one
  native WebRTC multi-participant adoption-gate timeout. Unused/Lean did not
  run because sequential runner stopped on test failure.
- Fixed-source native hold/transfer/successive-idle verification passes4/0
  seed0 (vxpipe-d-transfer-focused.log). Configured transfer actually holds
  caller with blocked destination preparation, retires idle immediately, ignores
  old deadline, then recovers with cancelled outcome retained once. Catalog
  recheck5/0seed515061 (vxpipe-d-catalog-recheck.log). Gateway isolated original
  seed rerun1757 currently active (vxpipe-d-gateway-handoff-recheck.log).
- Astra read-only Gateway review finds no causal evidence for an idle regression:
  missing adopt notification follows cue replay/readiness; no terminal phase
  evidence was captured. Do not increase timeouts or change transfer behavior
  without a repeatable failure and its state/trace evidence.
- Gateway isolated original-seed rerun1757 passes1/0(68excluded),
  vxpipe-d-gateway-handoff-recheck.log, without timeout or behavior changes.
  This does not prove broad-run stability; final full root rerun remains needed.
  Astra independent final hold/transfer/successive review run96280 owns lane
  next, log vxpipe-review-d-final-hold-transfer.log.
- Astra final independent native verification4/0(31excluded)seed0,
  vxpipe-review-d-final-hold-transfer.log. Transfer-hold finding closed; final
  source/behavior/ownership audit has no remaining validated issue. D closure
  still requires current-source gates and synchronized documentation.
- Started fixed-source sequential root verification99687 with fresh logs
  vxpipe-d-verified-{format,compile,credo,test,unused,lean}.log, stopping on
  first failure. No further runtime edits intended absent verified findings.
- Updated milestone/design/index status to distinguish implemented and
  independently reviewed D from pending final umbrella/Lean gates. All five
  completion boxes and index entry remain unchecked. Added concise configured/
  browser evidence summary; local Markdown target verification passes with
  no missing paths. Fixed-source root99687 remains active; static gates pass.
