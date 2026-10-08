# Call spec editor implementation

## Scope and setup

Implement the complete V → P → L → K → S → U → C → W → Z milestone. User authorizes
frequent coherent commits and GPT Luna pushnotify updates through zsh. No live tests
or live-provider environment access. Preserve the unrelated wrangler-cache labnote.
`bin/setup` completed dependencies, frontend assets, and development/test migrations.

## Design review

Reviewed the milestone, earlier editor review, tenant authoring and operator admin
prerequisites, direction contract, routing/styling documents and current Calls/Gateway
boundaries. Calls owns error projection; no transport reaches Persistence directly.
Exhausted revision retries need the same conflict response as a direct collision.
Private-material preflight needs a path, not only an atom. Old stored compiler errors
need a safe fallback. These are contract clarifications, not scope additions.
Later checkpoints retain the full source-model, Callpipe reuse, catalog, Storybook,
production integration and acceptance scope. UI review must use a concrete rendered
Storybook before production integration. No review of an unbuilt UI is claimed.

## Checkpoint V

- Red: Gateway focused suite (seed 738953) had four failures for missing field paths,
  opaque publish errors and conflicts incorrectly returning 503. Calls focused test
  failed because private material returned only an atom (seed 305742).
- Implemented a shared Calls error projection, fail-fast compiler projection,
  specific conflict/route/private-material statuses and private-field discovery.
  Validator/compiler reason strings were inspected: they are static descriptions
  or contain only project-defined numeric bounds, never submitted values.
- Green: Gateway's ten focused tests pass (seed 96941), including seven representative
  invalid sources on create/update, private prompt/URL/number non-disclosure, publish
  and saved compiler errors. Calls verification and root gates follow.
- Test setup corrections before the meaningful red run: CallSpec.new requires
  explicit identity/revision options; CallSpecRevision requires published_at.
  The environment provides python3, not python.

## Model abstraction clarification

Inspection found a tension between finite model listings, free-text Flux voices,
and preserving previously accepted configurations. The user selected public
pseudo-model IDs with adapter-owned concrete-ID construction. Deepgram.Speech
already accepts `flux` plus `options.voice`; use it as the public listing, with
recommended voice `hannah`, while preserving old concrete model IDs. This resolves
the specification ambiguity without changing the JSON schema or adding a second
frontend-only mapping. Future provider-specific combined IDs belong behind adapters.

### Checkpoint V exit evidence

Calls' ten focused tests pass (seed 778450). Root formatting, warnings-as-errors
compilation, strict Credo and unused dependencies pass. Full root `mix test` passes
3,326 tests with zero failures and 120 exclusions (seed 947553); Gateway's 589 tests
include existing outgoing and authoring coverage. The suite took about twelve
minutes, mostly local Call Engine and Gateway media/transport exercises. The
existing test-only archive_options default-argument warning is outside this change;
production warnings-as-errors compilation is clean. Documentation file links and
`git diff --check` pass. No frontend or state machine changed in V.

P's new, uncommitted model-contract test was run separately after the root run had
finished its Call Engine phase. Its 17 failures establish the missing model callback
and direct Flux public-selection behavior; this future-checkpoint red test is not
part of V's verified/committed tree. No P implementation is included in V.

## Checkpoint P implementation and verification

- Registry-driven red contract: 17 failures because models/0 was absent and direct
  Flux configuration did not accept the public model plus voice. The implementation
  now passes all 17 checks (seed 282748 before adding the guide fixture check).
- Every production STT/TTS/STS adapter and both Morse namespaces declares models.
  Pure configuration modules own declarations; sessions delegate. Model acceptance
  uses those declarations. Legacy fallback configuration stays unchanged.
- Flux lists one public `flux` model with recommended `hannah` voice, and builds
  concrete wire IDs internally. Old combined IDs remain supported. Free-text voice
  parameters also preserve Rime's `speaker` option. Defaults and rejected alternatives
  are recorded in docs/speech-model-catalog.md.
- Added the executable guide provider to the contract test: confirmed a red failure
  (seed 9180), then taught its configuration to accept/validate its declared model
  and synchronized the guide. Test-only probe adapters declare the required callback.
- Temporarily removed Cartesia STT's models/0 locally: `mix compile
  --warnings-as-errors` failed on the missing required callback. Restored the exact
  source and warnings-as-errors compilation passed. No broken callback is retained.
- Broader owning-child run: 670 provider, speech and inline-activation tests pass,
  zero failures, 22 excluded (seed 821225). Formatting, strict Credo and unused
  dependency gates pass. Full root default suite is running; P is not complete yet.
- One probe previously had no @impl annotations; adding only one triggered warnings
  for its other callbacks. Kept that probe's existing annotation convention instead
  of expanding unrelated test-fixture changes.

### Checkpoint P exit evidence

All five root gates pass. The default umbrella suite passes 3,343 tests, zero
failures, 120 excluded (seed 468087), including existing room and adapter tests.
No live tests ran. L implementation was applied after the root run had completed
its Agent Runtime phase; it is excluded from this checkpoint and receives a
separate full suite.

## Checkpoint L implementation

- Before implementation, nine catalog tests failed because ModelCatalog was absent.
  The focused catalog/selection group now passes 17 tests (seed 779757).
- Added a local snapshot listing for six runtime providers, text/tool filtering,
  one pinned recommendation each, and shared ModelOverrides declarations. Added
  the directly used llm_db dependency to Agent Runtime; the locked version is
  already present, so no lockfile change is required.
- Prepared L in temporary files during P verification, then applied it after the
  running root process had already finished Agent Runtime. P's evidence and commit
  exclude these L changes; L requires its own full verification.
- OpenRouter measurement after LLMDB.load: 260 models, first listing 100,335 us,
  ten warm listings 64,855–89,008 us, serialized result 36,125 bytes and temporary
  process-heap growth 141,848–229,520 bytes. No extra cache justified for operator
  listings; decision and limitations are recorded in docs/llm-model-catalog.md.
- Initial benchmark in child dev mode hit the existing umbrella runtime-config
  dependency on Persistence.CredentialKeyring. Re-ran in MIX_ENV=test, which isolates
  local model listing without provider credentials or network requests.

Agent Runtime suite passes 108 tests, zero failures, eight excluded (seed 256901).
Root formatting, warnings-as-errors compile, strict Credo and unused-dependency
checks pass. Full root suite is the remaining L gate.

### Checkpoint L exit evidence

All five root gates pass. The default umbrella suite passes 3,352 tests, zero
failures, 120 excluded (seed 226406). No live tests ran. K facade and endpoint work
began after this process had loaded the relevant preceding app tests; K changes
are excluded from the L commit and need their own complete verification.

## Checkpoint K implementation

- Red: eight facade tests failed for the missing module, the provider registry
  expectation failed for missing LLM declarations, four Calls tests failed for
  absent workflows, three tenant HTTP checks failed for missing routes, and three
  Console checks failed because the route fell through to the SPA.
- Added explicit `:llm` manifest ownership pointing at the existing ReqLLM runtime.
  The Call Engine facade resolves installed registry capabilities and delegates
  model listing to speech adapters or Agent Runtime. A fresh Elixir VM with only
  provider manifests proves absent implementation apps are omitted.
- Calls authorizes the exact tenant's admin or installation operator, then projects
  only credential-required/available flags. EffectiveServiceBindings now owns the
  trusted, validated inventory shared with the existing operator workflow. Tests
  cover inherited credentials, invalid tenant overrides, wrong tenant/scope, and
  private metadata exclusion.
- Gateway uses the existing call-spec-authoring feature gate and authentication;
  Console uses its operator-session pipeline. Both share value-free catalog errors.
  Owning focused suites pass: eight Calls checks, 14 Gateway checks and 16 Console
  checks (including existing service authoring) after the endpoint implementation.
- Onboarding needs model listings before tenant creation. The operator inventory
  workflow now includes the shared catalog; no second model inventory or new public
  unauthenticated endpoint is introduced. Frontend setupCatalog.json loses model
  IDs, and stories/tests use a captured descriptor fixture. Added parser and source
  recommendation tests before implementation. First frontend full run passes 222
  tests across 34 files, plus type check and lint.
- Browser startup required Chrome's `--no-sandbox` in this environment. The owned
  browser session and worktree Storybook port are used; no real sample call is run.
  Rendered desktop/phone inspection and full K root verification remain in progress.

### Checkpoint K verification progress

The final frontend run passes all 222 tests across 34 files after adding the
separate model/voice recommendation label. Type check and lint passed. Rendered
Storybook checks used headless Chrome at 1440×1000 and 390×844: correct Deepgram
STT, Gemini LLM and Flux/Hannah defaults; no horizontal overflow; blocked samples
have disabled load controls; the light theme renders the same recommendations.
No real sample call was started. Screenshots are temporary review artifacts.

The initial K umbrella run exposed an outdated OpenAI manifest equality assertion
(now includes :llm; all 30 Provider tests pass, seed 460817). That run also received
SIGTERM at 16:25:35 before finishing Call Engine; its apparent shell success is not
acceptance evidence. The full root suite has been restarted. A Storybook navigation
initially remained on its loader; the original server was still live, and reloading
then waiting for the rendered heading resolved it. No server restart was needed.

### Checkpoint K exit evidence

All five root gates pass. The completed umbrella suite exits successfully with
3,374 tests, zero failures and 120 exclusions (seed 487098), including all Calls,
Gateway and Console suites. Frontend and rendered evidence is recorded above.
No live tests ran. Checkpoint S files under callSpecEditor remain outside this
checkpoint and need their own validation.

## Checkpoint S implementation

- Added source types, preserving parser/serializer and deterministic graph projection.
  The three portable examples round-trip by JSON value without added defaults or
  layout fields; historical sources stay read-only. Six initial source tests and
  five participant-edit tests passed after missing-module red runs.
- Added immutable participant, capability, direction, tools, wait/media and variable
  edits. Participant renames rewrite structural references, not literal prompts.
  Variable renames update permissions, required fields and dial references. Removing
  a referenced variable leaves an explicit invalid choice for the operator to fix.
  The initial seven direction/field/variable tests failed on missing modules and
  then passed. A later red test exposed over-restrictive JSON Schema property names;
  property names now preserve the backend's arbitrary-string contract, including
  safe own-property handling of `__proto__`.
- Added 73 shared JSON cases executed by both Call Engine and Console validation.
  The first fixture run exposed two cases that triggered earlier unrelated backend
  failures; corrected the fixture setup to isolate each intended rule. All 73
  backend cases now pass. Client validation accumulated errors and passed 74 checks,
  including value-free messages. It covers UTF-8 byte limits rather than JS length.
  Additional policy/schema cases first failed 24 frontend checks before implementation.
- Error placement and feedback started with a missing-module red run; 30 tests
  cover node/tab/field labels, unknown-path fallback and every save/publish outcome.
  The UI still owns toast lifetime, focus and dirty-state handling in U/W.
- New source uses the development example's incoming web caller and text-capable
  agent, taking the recommended model from the supplied catalog. Voice additions
  use the adapter's voice parameter, including Rime speaker and separate Flux voice.
- A new portable-selection contract failed because Deepgram STT model and voice
  metadata alone omitted mandatory encoding/sample rate. Added adapter-owned public
  option defaults (linear16/48000) to that model descriptor, parser and captured
  fixture; this avoids introducing provider rules into the editor. The backend
  model/recommendation and shared-validation group passes 91 tests (seed 700026).
- Source/presentation/options focused frontend group passed 128 tests plus type
  check and lint. First full frontend run passed 348 tests across 41 files; the
  later property-name fix has its focused green test and needs a final full run.
  Root formatting, warnings-as-errors compile, strict Credo and unused-dependency
  checks pass. The complete umbrella suite is still running. No live tests ran.
- Some initial shell invocations used the repository root for npm or doubled paths
  from the assets working directory. Re-ran from the owning assets directory;
  only the observed expected failing tests are counted as red evidence.

### S verification follow-up

The final frontend run passes 349 tests across 41 files, plus type check and lint.
The first umbrella run (seed 647735) exposed an existing Cartesia room-test race:
its explicit second `Ingress.prepare_track` returned `unavailable`. Attachment
already declares the same input track and asynchronous room startup prepares it.
The explicit call can observe one policy/resource generation and submit after
startup has replaced that generation; the ingress correctly rejects the stale
snapshot. The unchanged isolated five-test file passed with the failing seed.
Removed the test's duplicate preparation and ad hoc collector: the synthetic
provider now acknowledges connection, then the test waits on the existing room
startup readiness acknowledgement before inspecting resources and pushing audio.
The corrected five-test file passes. No production speech/source state machine was
changed; no Lean lane is needed for this test synchronization correction. The
first full run remains failed evidence; a complete final run is still required.

## Checkpoint U foundation and copied baseline

- Preserved 17 required Callpipe component/story files byte-for-byte from commit
  2ea5ee0c503ef3690ad0d4e2139ee07bbbc985fd. Hashes and provenance are recorded in
  callSpecEditor/callpipe-originals. The initial `.source` suffix keeps this copy
  checkpoint usable without importing Callpipe-only dependencies or exposing its
  excluded features. Adaptations will move these files to strict TypeScript.
- Installed React Flow and all 25 requested standard registry controls (26 files,
  including the toggle dependency) using the shadcn CLI's new-york Radix style.
  Registry files are unchanged after CLI generation. The current registry uses
  upstream `cn` and `radix-ui` packages; these are recorded in the assets lockfile.
  Existing Console buttons remain unchanged. Added tw-animate-css for the registry
  motion utilities, TS/Storybook/Vitest aliases, and a narrow lint exception for
  intentional registry variant exports. No product custom-control replacement.
- Read the official CLI/components.json and React Flow guides, and the installed
  CLI help before use. Added a red test for editor-owned body portal theme lifetime,
  then a restoring EditorTheme wrapper. Console's existing tokens now supply the
  standard semantic shadcn tokens in both themes, including body-mounted portals.
- The theme-check composition renders form, disabled/error states, dialog and
  popover at desktop/phone dimensions. Headless Chrome verifies dark desktop and
  light 390px phone; portal computed backgrounds/foregrounds match their theme,
  and the light phone has no horizontal overflow. Waited for animation completion
  before final portal screenshots. Browser errors are empty. Old Storybook handle
  was confirmed terminal after connection refusal; started a new worktree server.
- Type check and lint pass. Storybook build succeeds. All 350 frontend tests in
  42 files pass. Rendered onboarding at 390px retains the same catalog defaults
  (including Flux / hannah), has no horizontal overflow, and has no editor body
  theme attribute after navigation.
  The S final umbrella run is still in progress; its corrected full Call Engine
  suite passes 2,066 tests, zero failures, 74 excluded.

## Source-model final acceptance

The final umbrella process exited successfully: 3,448 tests, zero failures,
120 excluded, seed 197178. All five root gates pass on the source-model changes.
No live tests ran. Exit S is complete. The original failed run remains recorded
above; the readiness-synchronized Cartesia test passed within the full suite.

## Copied header and toolbar adaptation

Moved the committed original header/toolbar into strict TypeScript, preserving
the floating layout and name dialog. Replaced Callpipe translations and local
controls with Console registry primitives; removed test-call/chat actions. Added
revision/published badges, unsaved/read-only state and the issues action. Save
stays actionable with client errors so the editor can explain the blocked save.
Seven focused tests failed first because the adapted module was absent, then
passed. The initial test run exposed missing explicit Testing Library cleanup;
adding the existing suite's cleanup pattern fixed test isolation.

The remaining U2 shell files and component stories now adapt the committed
Callpipe baseline. The original 320px card and 34rem inspector geometry remains;
S's deterministic graph order replaces mutable Dagre layout. Positions and
measured dimensions live only in the canvas. Drawing rejects non-agent sources,
self/missing/entry destinations and read-only documents, consistently with S's
transfer edit boundary. Entry edges cannot be removed or reconnected.

The first browser pass exposed hidden cards because reconstructed nodes dropped
React Flow's measured dimensions. Retaining measurements and memoizing graph
projection fixes the display; unchanged measurement notifications are ignored.
The copied static NodeCards story also rendered Handles outside node context;
its cards now use actual React Flow nodes. Final browser console/errors are clear.
React Flow CSS is imported in the component layer so semantic utilities apply to
handles; its controls are themed and moved above the toolbar on phones. Upstream
attribution is retained. The mobile inspector uses the standard Sheet.

Eleven focused UI/projection tests pass after missing-module red runs. All 361
frontend tests, type check, lint and the final Storybook build pass. Inspected six
stories (Header, HeaderSaving, NameDialog, Toolbar, NodeCards, CanvasShell) at
1440x1000 and 390x844: no horizontal overflow. A real pointer drag from intake to
a newly added agent produces transfer:intake:agent_1 alongside the locked entry
and existing specialist edges. Name editing produces Reception and unsaved state;
arranging and opening/closing the phone Call settings Sheet work. Inspector body
content is intentionally a composition slot pending U3–U5, not a finished page.

The earlier Storybook process was confirmed terminal; its port check still
refused the old port after HTTP stopped responding. The current development
server runs on port 6021 in an owned tmux session for persistent browser checks.
No production route changed and no live tests ran.

Post-shell format, warnings-as-errors compilation, strict Credo and unused-lock
checks pass. A fresh full default umbrella run is underway after this frontend
checkpoint; the previously completed source-model umbrella run remains green.

## U2 umbrella follow-up: STS test precondition

The fresh umbrella run (seed 991936) failed the existing direct-output policy
revoke test while its authority variant passed. The test expected a sink
interruption after receiving the logical STS turn-start event, but the owned
output-delivery task had not necessarily registered its first frame with the
sink. The sink returns wrong_turn for an interrupt before that registration;
the failure mailbox shows the frame arriving after the interruption publication.
The unchanged two-case isolated selection passed with the same seed.

Both variants now await the first sink frame and the existing owned-delivery
acknowledgement before queuing the second reply and revoking output. This makes
the tested sink-interruption precondition explicit without sleeps or production
state-machine changes. The full 63-test STS capability file passes with seed
991936. The first umbrella run remains failed evidence; final umbrella acceptance
must be rerun. No Lean run is needed for this test-only synchronization change.

## Checkpoint U3: direction and policy panels

Added field compositions from the standard registry controls and adapted the
committed Callpipe InspectorShell. Direction editing preserves participant data
and requires an explicit phone service and agent before switching to outgoing.
Media fields expose call-wide and presence policy shapes, wait sounds distinguish
omitted defaults from explicit silence, and Advanced exposes tool visibility,
per-tool overrides, duration and transfer timeout. Optional values are omitted
only when explicitly cleared; read-only documents disable all mutation controls.

Seven focused tests started red on absent modules. Reading the backend policy
contracts identified two important UI distinctions, then additional red cases
confirmed the initial controls were wrong: an explicit empty route map denies
all pairs (inheritance is at the map level), and wait_sounds: null silences every
slot. The controls now preserve both meanings across edits. Routing requires an
explicit Restricted selection; each source offers Nobody or All other
participants, with checkboxes for a custom set. The full frontend suite passes
370 tests; type check, lint and Storybook build pass.

Rendered six composition stories at dark 1440x1000 and light 390x844: direction,
media/recording, wait sounds, all-silent, invalid timeout and historical read-only.
No horizontal overflow. Corrected shrinking inspector headers and waited for the
Storybook play function and dialog/Select dismissal animations before final
screenshots. The outgoing dialog requires service selection and produces a
callee/agent direction in the browser; final browser errors are empty. These are
U3 component compositions, not the complete Call settings tabbed inspector;
Defaults and Variables remain before U3 can be checked off.

The complete U2 umbrella rerun exited with two failures, seed 991936: the STS
precondition fixed in ca407ea0, and the already-recorded five-participant WebRTC
listener-reconnection case (missing 250 Hz audio after closing the original
monitor connection). The transfer milestone explicitly defers investigation of
that latter case. Existing coverage and runtime behavior are retained; a scoped
same-seed reproduction is running, followed by a new complete default run.

The unchanged isolated five-participant WebRTC case passes with seed 991936
(1 test, 68 excluded). This does not establish or repair its intermittent cause.
A full default rerun with that seed is now active after ca407ea0.

Final review added two red cases for supported prototype-shaped identifiers:
a participant named constructor with an empty route map, and a tool named
__proto__ receiving a visibility override. The UI now uses own-property lookup
and computed-key updates instead of treating inherited object members as source
data. All nine panel tests pass. Final rendered policy interaction confirms
recipient checkbox changes and no horizontal overflow; browser errors are empty.


## Checkpoint U3: catalog-driven model controls

Added shared capability fields and a Defaults panel. A provider selection uses
its catalog recommendation, including adapter-owned options and voice parameter.
The source keeps Deepgram model flux and options.voice separate. Model changes
reset model options to the chosen descriptor while preserving the same provider's
credential name and provider_options. Provider changes replace the whole selection
so stale credentials and provider-specific options do not cross providers.
Opening a saved selection performs no defaulting; legacy combined IDs remain
visible until explicitly replaced. Default edits leave participant overrides intact.

Six new tests began red on missing controls, then passed along with the existing
seed tests after implementation. Full frontend verification passes 376 tests.
Type check and lint pass; the Storybook build passes. The model-selection helper
was extracted from seed.ts so new specs and explicit picker changes share the
same descriptor semantics. Generic structured options remain a separate U3 task;
these controls preserve options they do not yet expose.

Rendered empty, saved-voice and legacy-model compositions in dark desktop and
light phone layouts. Browser interaction changed Deepgram to Rime, edited its
speaker and selected OpenAI STS with its declared free-text voice recommendation.
A synthetic, clearly named story exercises the future known-voice-list contract;
all currently captured runtime fixture descriptors use free-text voices or none.
No horizontal overflow or browser errors in the final inspected states.

The design hook also reported 23 existing admin.css token/radius findings while
following the story's stylesheet import. This checkpoint does not change that
stylesheet; existing branding and unrelated Console styles remain as requested.
No design-rule suppression was added. Format, warnings-as-errors compilation,
strict Credo and unused-lock checks pass. The full umbrella rerun ended early with :terminating after Gateway reported
568 tests and no failures; Console did not run and the result is not acceptance.
The log does not establish the termination cause. After confirming that process
had exited, started one full seed-991936 rerun in an owned persistent tmux session
with a separate exit-status record. No live tests ran.

The voice-list screenshots initially caught the opening transition. Waiting for
computed opacity 1 produced readable final menu captures in both themes.


## Checkpoint U3 complete: structured options and Variables

Added typed JSON value compositions for options/provider_options, reusing the
standard Input, Select, Button and Label primitives. Nested objects and arrays,
booleans, numbers, strings and null remain editable without raw JSON. Explicit
empty objects remain distinct from omitted options. Colliding key renames leave
the old value intact and show an error, including prototype-shaped keys and the
voice parameter reserved for its separate control. The same value composition
edits schema enum values; no custom primitive replaces a registry component.

Adapted the committed Callpipe flow-level inspector to six source-backed tabs.
Its scrolling tab bar and inspector geometry remain; unsupported chat, workspace,
knowledge and retention controls are removed. Variable rows extend the original
name/type/required/remove composition to named sections and the supported nested
schema subset. Section/field renames use S's reference rewrites. A shared table
exposes section-by-agent permissions. Existing grants to missing sections remain
visible and removable; granting new access still requires a declared section.

Focused red runs covered absent value/schema/tab controls, capability integration,
voice-key collisions, stale grant removal in both pure source and UI tests, and
constraint visibility. The final suite passes 391 tests in 51 files. Type check,
lint and Storybook build pass. A check briefly ran while the next test's module
was still absent and failed; final complete verification supersedes that partial
worktree check. Constraint controls now show relevant fields plus every stored
constraint, so changing a schema type does not discard unusual existing keywords.

Rendered eight inspector stories and five model/option compositions in dark
1440x1000 and light 390x844. Inspected nested JSON/schema content and the permission
matrix while scrolling; browser edits changed an array string and a section grant.
No horizontal page overflow. Initial inspection found selected Advanced outside
the scrolling tab bar; a browser assertion failed before an active-tab scroll
fix and passes afterward. Labels wrap long paths and the active indicator stays
within the bar. Two Storybook hot-reload errors (cannot render when not prepared)
were retained by the original browser session; a fresh session is used to check
current rendering separately. These were preview-runtime errors during edits,
not evidence of a product exception or failed source mutation.

The persistent full default umbrella run completed with exit 0: 3,448 tests,
zero failures, 120 excluded, seed 991936. Format, warnings-as-errors compilation,
strict Credo and unused-lock checks also pass. The prior partial/failed runs stay
recorded above. The deferred five-participant reconnection case passed this run;
this does not prove its intermittent cause was repaired. No live tests ran and
no production speech/source-cutover state machine changed. U3 is checked off;
participant inspectors and the complete error/page/review checkpoints remain.

Fresh Chrome session rendering the nested-variable inspector reports zero browser
errors after the final changes. The original session retains its earlier preview
hot-reload errors; they were not discarded as a substitute for verification.


## Checkpoint U4: Entry and human inspectors

Adapted the committed Callpipe inbound and human inspector snapshots. Entry now
exposes caller/callee connections, opening text with explicit TTS selection or a
file URL, and outgoing ring timeout. Human destinations expose service, fixed or
variable phone routing, description, private briefing and the one call-wide
transfer attempt timeout. Both expose all five participant capability overrides
and presence policy through the existing standard controls. Renaming and removal
reuse the source layer's atomic reference edits; entry has no delete action.

Focused red runs first failed on missing inspector modules, then caught optional
text clearing as invalid empty strings, missing inherited-default context after
an override, and an inherited provider named `__proto__` triggering prototype
lookup. The implementation removes explicitly cleared optional text, retains
call-default context alongside an override and uses own-property catalog lookup.
Opening saved source preserves nulls, omitted dial admission and combined legacy
model IDs. The original snapshots remain recoverable at the committed baseline.

Nine stories rendered in Chrome at dark 1440x1000 and light 390x844; all eighteen
views were inspected with no horizontal page overflow. A scrolled phone view
verified changing the opening voice to haley while keeping the Flux model. The
first browser fill ran before the preview mounted and found no control; waiting
for the mounted editor resolved that inspection race. Existing admin.css design
hook findings remain the previously recorded unrelated Console styles.

Initial concurrent frontend verification ended with six 5-second test timeouts
and the deliberately added missing-default assertion (394 passed, seven failed).
The focused inspector run passed ten tests once those overlapping checks ended;
the later inherited-provider regression was independently confirmed red. Root
non-test gates launched through an exec session exited 143 before completion;
the persistent rerun passed. Neither incomplete run is acceptance evidence.

Final focused verification passes all eleven inspector tests. The full frontend
suite then passes 402 tests in 52 files with one worker, followed by type check,
lint and the final Storybook build. No timeout settings were relaxed. The full
default umbrella suite passes 3,448 tests, zero failures, 120 excluded, seed
991936. The other four root gates pass with explicit exit 0. No live tests ran;
this UI work does not change a production speech/source-cutover state machine.

Additional Chrome interactions verified the human deletion confirmation and
removal, and a participant voice override while retaining visible call-default
context. The current browser session reports zero errors. U4 is checked off;
Agent inspector, full error presentation, page stories and user review remain.


## Checkpoint U5: Agent inspector

Adapted the committed Callpipe agent inspector to six source-backed tabs: Prompt,
Voice and model, Variables, Transfers, Tools and Presence. The original tab bar,
transfer destination search, tool list and source/tool/options dialog pattern are
retained with standard registry primitives. Prompt uses a plain textarea; shared
capability, section-permission and presence controls replace the original profile
and variable-access concepts. Agent key edits and deletion reuse atomic source
reference rewrites. First-message omission shows the direction-dependent default
without inserting it into saved source. Transfer-history edits clear mode-specific
turn counts; loading a saved null preserves it.

The focused red run found that canvas connections and source transfer edits allowed
a human with start-call admission as a transfer destination. Both now share the
transfer-destination rule used by the new picker: another agent, receive/transfer
web human, or dial/transfer phone human (phone admission may be omitted). Existing
invalid destinations remain removable. This is a frontend source-edit rule, not a
production speech or source-cutover state-machine change.

Tool names remain free text; MCP integration names come from lookups. Host tools
keep their registered name as the local key, matching compiler resolution. The
modal replaces type-specific fields when changing source, preserves explicit or
omitted conversation mode, and rejects reserved/colliding keys on submission.
Tool-key renaming moves its visibility override atomically, including an obsolete
visibility entry at the new key; a focused red case caught that collision before
the fix. Tool removal uses the existing visibility cleanup. No remote tool discovery
or provider call is performed by these Storybook fixtures.

Focused UI/source verification passes 23 tests, with type check and lint. Ten
stories were rendered at dark 1440x1000 and light 390x844; all twenty views were
inspected with no horizontal page overflow. The bounded visual pass moved Prompt
first and gave it ten rows, using the standard textarea's native sizing. Existing
admin.css hook findings remain the previously triaged unrelated Console styles.
The six affected Prompt views were reinspected after that adjustment. Chrome
interactions at both widths verified searching and adding a transfer destination
and editing an MCP tool through its Tool and Options steps, including a local-key
rename. The current browser session reports zero errors.

All five root gates pass, including 3,448 default umbrella tests with zero failures
and 120 excluded (seed 991936). Storybook builds successfully. The first full
frontend run passed all 418 assertions but failed on a deferred Radix focus-scope
unmount event crossing jsdom realms between files. The shared test setup now
awaits the queued timer turn before closing each file, allowing that lifecycle
cleanup to finish in its original realm. This changes test teardown only; no
dependency behavior is mocked or suppressed. The full rerun passes all 418 tests
in 54 files, type check and lint with exit 0. No live tests ran. U5 is checked off;
full error presentation, page stories and user review remain.


## Checkpoint U6: Error and source surfaces

The previous goal turn completed and committed U5 as b54c6211. U6 begins with
focused red tests for issue counts and persistence, field focus and placement,
recovery actions, JSON export, and header/phone-inspector behavior. An initial
test-file creation used a root-relative path from the assets directory and wrote
nothing; the corrected command created the test and confirmed the missing module
as the expected red failure.

Client issues remain distinct from the last field-related backend failure. Pure
helpers count canonical node/tab locations, retain a server error through unrelated
edits, and remove it when its source value changes. Private-material failures use
client text rather than echoing the backend reason. Permission, network, conflict
and malformed-request failures are excluded from field-error state.

Visible inspector fields register their source paths with an issue scope. Exact
controls own inline errors; collection paths use the nearest represented control,
and unrepresented errors have a focusable summary in the active tab. A newly
opened tool dialog owns a duplicate path ahead of the underlying tool card. Red
tests caught both missing dialog/constraint revelation and the duplicate-path
focus conflict. Show now reveals tool steps and collapsed constraints before
focusing. A request identifier prevents edits from repeatedly stealing focus.

All inspector tabs show counts without adding error messages to hidden panels.
The existing Console toast gains an optional standard Button action; the editor
provides Show, Retry, Open services and Reload labels. JSON uses a standard Sheet
and read-only textarea with exact source copy/download. Publish requires an
unchanged saved revision without client errors; Save remains actionable for
client-error feedback. An external focus request can open the phone inspector.

These components still need complete editor/controller integration and its action
lifecycle tests in the next U6/U7 work. U6 remains unchecked pending that evidence.
Full frontend and rendered checks are in progress.


Additional focused red cases caught duplicate issues with differently ordered JSON
keys, focus restoration after closing drawers, and replaying a completed Show
request when its field disappeared. Deduplication now compares issue values,
drawers return focus to their opener unless Show intentionally moved it, and
focus moves only toward a more precise target for the same request. Field-error
assignment is computed once per scope render rather than once per field.

A pure action-feedback lifecycle retains backend field failures across retry and
publish outcomes, clears them after successful saves, preserves authoring/session
gates, and avoids attaching late errors to fields changed since submission. Its
five focused tests pass.

The initial complete frontend run passes 442 tests, type check and lint; subsequent
focused cases pass, and a final full run is queued after the existing root run.
The Storybook build passes. Nine error/source stories were inspected in dark
desktop and light phone views, plus the canvas-count story at both sizes. Chrome
interactions verify drawer-to-tab focus, client-blocked Save feedback, unmappable
errors opening the list, backend errors clearing only after the affected edit,
and successful copy feedback. The downloaded JSON exactly matches the displayed
source. Clipboard readback was denied by browser permission; the unit test checks
the exact payload passed to clipboard.writeText. The current browser has no errors.
One interaction script clicked during the Sheet entrance animation; waiting for
that animation resolved the observation. A later close-focus run was interrupted
by Storybook hot reload during a source edit and passed when rerun after editing.

Execution permissions changed during final verification: the Git directory became
read-only and the existing tmux socket became inaccessible. Source edits and log
reads remain available. No attempt was made to bypass those restrictions. Existing
root/frontend jobs were not restarted; their output and exit files remain the
authoritative evidence. The checkpoint cannot be committed under these settings.


Final verification completes with explicit exit 0 for the full frontend lane
(450 tests in 58 files, type check and lint), Storybook build, the root test lane
(3,448 tests, zero failures, 120 excluded, seed 991936) and the other four root
gates. No live tests ran. No production speech/source-cutover state machine
changed. Final browser interaction replay passes both widths with zero browser
errors; the final close-focus replay completed desktop checks before the execution
environment changed, while the earlier complete replay verified both widths.
All twenty component views and four interaction screenshots were inspected.
Milestone U6 remains unchecked until full editor/controller wiring and other
action-failure feedback are implemented and verified. Changes are unstaged and
uncommitted because the current environment exposes the Git directory read-only.

### U6 continuation — draft lifecycle and inspector dispatch

Added reducer tests before implementation; the red run failed on the absent
editor-state module, then nine tests passed. The reducer retains a submitted
snapshot separately from the current draft, advances revision metadata without
discarding in-flight edits, blocks invalid/read-only/concurrent actions, and
ignores stale results after explicit reload. Malformed success metadata must not
claim a save. Calls allocates revisions when saving; inspection confirmed no
expected-revision argument belongs in the frontend contract.

Added transport-hook tests before implementation; the absent use-editor import
was red, then seven cases passed. An injected transport receives the exact source
snapshot and AbortSignal. Duplicate clicks issue one request; synchronous throws
and rejected promises retain edits and produce retry feedback; retry uses the
current draft. Reload/unmount abort pending work; late results cannot update the
replacement document or trigger session handling after unmount. Session expiry
notifies the host once and retains the draft. The full frontend suite then passed
466 tests, type check and lint. Initial lint found unused mock parameters; typed
mock signatures fixed them without suppression.

Copied/adapted the remaining inspector dispatcher and selected-edge presentation.
Five focused tests were red on the missing dispatcher, then passed for selection
routing, requested tabs, transfer deletion, the locked Entry edge, read-only
transfers and a safely rendered stale selection. The generic inspector is a stale
selection summary because all supported participant kinds have dedicated editors.
Type check and lint passed after this addition.

Fresh required root verification cannot start under current restrictions:
Mix.PubSub fails opening its local TCP socket with eperm. The prior 3,448-test
green run covers the earlier component checkpoint, not these new files.
An agent-browser snapshot of the existing session fails because its socket
directory is read-only; new inspector composition has not been rendered-verified.
No bypass was attempted. Git metadata remains read-only, so no commit is possible.
U6/U7 remain incomplete; full-page composition, other action-failure feedback,
recovery/navigation guards, page stories and prototype review still remain.

Final frontend verification for this increment passes 471 tests in 61 files,
TypeScript checking and ESLint (exit 0). git diff --check passes. No live tests
ran. The existing GPT Luna notification agent sent the checkpoint progress update
through pushnotify successfully; no implementation or Git work was delegated.

### U6/U7 continuation — full editor prototype

Started with eight full-editor boundary tests, red on the missing flow-editor
module. The composed editor uses the existing source reducer, injected transport,
canvas, inspectors, issue scopes, drawers and toast. The tests cover exact source
submission, revision/published badges, client-blocked requests, Show focus, backend
field-error lifetime, Retry with current edits, Back/Reload confirmation, and
add/connect/rename/delete transfer synchronization in exported JSON.

Additional tests exposed two integration issues before their fixes: adding a
participant on a phone selected it without opening the inspector; and an old
Reload action remained enabled during a new save. Dedicated inspector requests
now open the phone sheet after Add or Show. Recovery actions disable during writes
and reloads. Show remains available. Sixteen full-editor tests now pass, including
phone field focus, unmapped errors, Open services confirmation, failed reload
retention, browser unload cleanup, and tool/rename failure feedback preserving
local drafts. Seven existing error-surface tests pass alongside them.

Added three page-state tests before implementation (red on the missing module)
for loading and spec/catalog load failures with page Retry. Added a red hook test
for invalid-request defect logging, then logged only a fixed message plus action
name; source and backend reason are never logged. The hook's eight tests pass.

Adapted Callpipe's full-page story pattern into 34 stories covering default, new,
loading, spec/catalog failures, client issues/blocked save, every save/publish
outcome row, outgoing/published/historical/long/narrow states, and Add, Rename,
Draw transfer, Show and issues-list interactions. These stories inject transport
outcomes through the actual editor; they do not wire production endpoints.

Storybook build is blocked before bundling: the existing main configuration cannot
spawn bin/worktree-port (EPERM). The first command used the wrong npm script name;
the corrected build-storybook invocation reached that environment failure.
agent-browser still reports its socket directory read-only, so the 34 new stories
and new full-page layout/interactions have not been rendered-verified. Prior
component screenshots do not prove this increment. No alternate process or Git
write mechanism was used. Git remains read-only and no commit was created.
The existing admin.css design-hook findings remain the previously triaged global
styles; this increment does not change that stylesheet.

U6/U7 remain unchecked pending the missing build/render evidence. U8 requires the
rendered pass before user review. C/W production integration remains behind that
review gate; no live tests were run.

Final frontend lane passed 491 tests in 63 files, TypeScript and ESLint (exit 0).
The repeated root gate attempt failed at Mix.PubSub's local TCP socket (eperm).
git diff --check passes. The milestone and index distinguish the earlier verified
component checkpoint from the currently unverified full-page prototype.

### Verification blocker audit

The preceding goal turn made implementation progress: full-page composition,
34 stories, the phone Add fix, recovery concurrency fix and 491 passing frontend
tests. This audit rechecked the actual worktree, milestone gate and last commit
(b54c6211, Agent inspector). Storybook still fails before bundling when spawning
bin/worktree-port (EPERM), and agent-browser still reports its socket directory
read-only. The filesystem policy still exposes Git metadata read-only.

These environment restrictions have recurred over more than three consecutive
goal turns. Source implementation could proceed in earlier turns, but the next
required work is now the missing build, umbrella verification, rendered prototype
inspection and commit. U8 explicitly requires browser inspection followed by user
review before C/W production integration. No acceptance evidence permits crossing
that gate, and additional status-only retries would not advance the milestone.
The goal is blocked pending an execution environment that permits the required
processes, local sockets and Git writes. The implementation remains preserved and
uncommitted; no live tests ran.

Resume by running the standard root gates and Storybook build, inspecting the new
page stories at desktop/phone widths with agent-browser, fixing any findings, and
committing the coherent U6/U7 checkpoint. Then obtain and record U8 review before
implementing C, W and Z. The milestone remains incomplete.

### U6/U7 verification resumed

Execution permissions now permit local sockets, subprocesses and Git writes. The
Storybook production build passed for the full-page prototype. The root gate
chain is running with seed 991936; formatting, compilation and Credo passed,
and the Call Engine suite passed 2,066 tests with zero failures (74 excluded).
The remaining umbrella suites are still in progress.

The user requested resource checks before heavy jobs and no parallel heavy work.
After observing CPU pressure during the desktop browser sweep, paused its owned
runner and replaced the polling Vite server with a lightweight static server for
the completed Storybook build. The root suite now runs alone; the phone sweep
will resume after it finishes and resources are checked. Desktop stories checked
so far report finished interactions and no document overflow. Portal screenshots
must be captured after their entrance animation settles; a finished Storybook
play function alone does not establish the final rendered sheet position.

The resumed root command completed successfully: all five required gates pass,
including 3,448 tests, zero failures and 120 excluded (seed 991936). The Gateway
suite passed 593 tests, Artifacts 20, Persistence 214 and Console 241. After the
root process exited, available memory recovered to 4.7 GiB and the paused browser
runner resumed. No live tests ran; no speech/source-cutover state machine changed.

All 34 page stories now have dark desktop (1440×1000) and light phone (390×844)
rendered inspection. Story play functions passed and no document overflow was
reported. The desktop IssuesList navigation timed out while its runner was
intentionally stopped; a separate capture passed after resumption. Reopened the
source drawer for final desktop/phone inspection instead of relying on captures
taken at the start of its entrance animation. The browser reported no page errors.

Additional browser interactions passed: Back/Keep editing and confirmed departure,
revision-conflict Reload with unsaved changes and replacement by revision 4,
Open services with a discard confirmation, catalog-load Retry, phone Back
cancellation, successful clipboard feedback, and a real downloaded JSON containing
the added agent and drawn transfer. The temporary recovery harness needed corrected
selector quoting, scoping around Storybook's hidden headings, and an explicit wait
for a closing modal to unmount before accessing background links. These were
verification-script corrections; no implementation changes were needed.

U6/U7 are now checked off. The frontend lane's 491 tests, TypeScript and lint
results remain applicable because no source changed during the resumed build and
browser pass. U8 remains unchecked: the complete prototype is ready for the user's
required review. The static Storybook server remains available on port 6021 for
that review. C/W production integration has not started.

### Production integration authorized

The user explicitly instructed completing product integration and everything else,
with their UI review deferred until later. This supersedes the U8 stop: the
prototype remains browser-verified, but no user UI approval is claimed. Updated
the milestone and index accordingly. Continue C → W → Z with red-green tests,
frequent coherent commits, no live tests and serialized heavy checks. Resource
check before starting: 4.5 GiB available RAM; load average about 2.2.

### Console endpoint checkpoint

Added installation-operator latest/historical reads, create/append/publish routes,
and credential/telephony/MCP name lookups. Focused tests were red for missing
facades/routes and then green: Calls 11, Console 9, configured MCP names 2.
A separate privacy regression first exposed source prompts in Phoenix request
logs; filtering the source parameter made it green. Cross-tenant reads, writes and
publication return 404. Invalid sources preserve structured paths and safe reasons;
configuration/store exceptions return fixed errors. No remote MCP discovery or
live providers are called. All five root gates pass: 3,458 tests, zero failures, 120 excluded, seed 991936.
Credo checked 1,217 files without issues. No live tests ran.

### Production wiring red/green

New API tests failed on the missing client module and five route tests failed on
missing editor pages before implementation. The first eight API/route tests are
now green. The list action test was red for the missing New call spec link, then
passed with separate editor and call-count links. Router regression tests exposed
captured initial App props after moving to the data router; context now supplies
current props while retaining a stable router. This preserves existing request
injection and session handling. Added history-back and in-flight create-save
coverage to verify unsaved data survives URL replacement and cancellation.

Full heavy jobs remain serialized; bounded single-worker focused frontend tests
ran while the long default Gateway lane was active, with over 4 GiB available.

The history-back test exposed a real confirmation race: Radix closes an accepted
alert dialog after its action, which called the stale cancel callback and reset
React Router's proceeding navigation. Tracking approved departure until the next
blocked navigation fixes it. Both cancellation and confirmed browser Back pass.
First-save URL replacement also preserves a newer draft typed during the request.

Production assets built successfully and the real local Console was inspected with
agent-browser at 1440x1000 and 390x844. Created, saved and published incoming specs
at both widths; edited/reopened immutable revisions; verified revision 1 stayed
published while later drafts were saved; inspected explicit revision URLs and
Continue editing latest revision. Prompt and outgoing ring-timeout validation
blocked saves and retained edits. Outgoing conversion uses a configured synthetic
phone application and requires an agent handler. The browser recorded no errors.
The populated list, new, edit, published, historical, validation and outgoing states
have rendered captures named vxpipe-production-* in temporary verification output.

Resizing an already-open desktop canvas to phone width initially left participants
off-screen. A focused test was red for missing resize behavior, then green after
fitting the viewport when the available canvas dimensions change. Ordinary
rerenders preserve pan/zoom. A fresh production build and rendered resize check
confirmed both nodes remain inside the phone viewport. Browser automation needed
explicit waits for nested sheet/dialog/popover animations; early captures and
failed selectors were replaced by settled-state inspections.

All three examples (development, sts-morse, outgoing-morse) were created through
the tenant API, opened in the production editor and saved without edits. Each
retained both its exact JSON value and original source digest. The outgoing example
initially returned the expected missing-service credential error; provisioning a
local synthetic tenant phone application allowed the authorized round-trip. No
carrier request was made. A newly created/published editor spec's caller route
prepared and started a local Gateway session: both requests returned 201 and the
call entered running state. It used a synthetic tenant credential, waited for input,
and received no input or provider generation request. This is local call-start
acceptance, not live-provider interoperability testing.

The temporary Console server and its watchers were stopped after browser checks;
the temporary login/API-key file was removed. No live-provider environment file was
read or changed, and no live tests ran. Final frontend verification passes 503 tests
in 66 files, TypeScript and lint without warnings. The final five root gates are
running serially after that frontend lane; resource checks showed 3.9 GiB available
before launch. No speech/source-cutover state machine changed, so Lean is not
required for this checkpoint.

Final gate chain completed successfully: format, warnings-as-errors compile, strict
Credo, the umbrella default suite and unused-dependency check all pass. The suite
reports 3,458 tests, zero failures, 120 excluded (seed 991936); Console has 248
tests, Calls 214, Gateway 593 and CallEngine 2,068. Final frontend verification
passes 503 tests in 66 files, TypeScript and lint. Documentation links and staged
whitespace checks pass. Milestone W/Z, acceptance checks and the index are now
complete. The user-deferred UI review is recorded as a disposition, not approval.
The unrelated wrangler-cache-repair labnote remains untouched and untracked.
