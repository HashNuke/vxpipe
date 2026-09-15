# Zenmux tenant credentials

## Scope and starting state

- Started from committed `84dd938` with a clean worktree. The user's scope reminder matches
  the milestone and source-backed inventory: migrate existing authentication only.
- Checkpoint 5 depends on the shared credential source, so its remaining Zenmux migration can
  ship independently of unfinished carrier readers. Google/Deepgram are already migrated;
  direct OpenAI/Anthropic and other SDK catalog auth modes remain excluded.
- Existing source evidence: `b5917ae` Engine `AgentModelProfileTest` and Agent Runtime native
  request test introduced by `e9d3ab4`. Preserve the Zenmux model path, generation options and
  nested provider routing with one Zenmux API key. Reuse the current cipher, source and adapter.
- Added focused tests before implementation for inline translation, existing adapter creation,
  encrypted provisioning, save/prepare/persisted-plan resolution, and actual request authentication
  with conflicting ambient settings. No live provider request is authorized by these checks.

## Verification

- Red: Agent Runtime focused group 5 tests, 2 expected failures (Zenmux translation absent);
  Engine constructor group 5 tests, 1 expected failure (Zenmux runtime selection absent).
- Persistence red: 28 tests, 2 expected failures, 2 excluded (unsupported credential payload
  and inline selection). All three red groups preceded implementation.
- The first implementation preserved JSON string keys inside the native routing map, but installed
  ReqLLM/NimbleOptions requires atom keys there. A probe using only synthetic public options
  exposed that validation error. Translate only the five already allowlisted routing keys to
  fixed atoms after validation; never intern arbitrary input. Wire JSON remains unchanged.
- Green: Agent Runtime selection/request group 5 tests, Engine constructor group 5 tests,
  Persistence store/inline/CLI group 33 tests (2 excluded); zero failures in each.
- Independent design review confirmed the four existing integration boundaries and no need for
  new auth machinery. GPT 6 Astra xhigh implementation review found no production blocker and
  one fixture correction: ReqLLM reads the application key from `:zenmux_api_key`, whereas
  `:zenmux` owns the endpoint. Seed/restore those exact keys independently. No additional
  authentication support or changes to the shared credential machinery were needed.
- Static root gates pass: format, warnings-as-errors compilation and strict Credo. Final root
  testing and unused-dependency verification remain pending.
- After the review fixture correction: Agent Runtime suite 95 tests, zero failures, 4 excluded.
  Calls suite 81 tests and Persistence suite 99 tests (6 excluded) also pass.
  Documentation checks pass for 188 local links/anchors, two JSON examples and seven-checkpoint
  status. Checkpoint 5 is recorded as partial until final verification; no milestone completion
  is claimed by the source inventory or this implementation commit.
- Earlier full umbrella native Morse failure remains
  recorded in the service-registration labnotes; this checkpoint does not change native audio.

## Final root verification at `14abe74`

- Ran all five required commands sequentially from the umbrella root. Format, compile with
  warnings as errors, strict Credo and unused-lock verification pass.
- `mix test --preload-modules --max-requires 1 --max-cases 4 --seed 235296` completed
  **1,547 tests, one failure, 33 excluded**: MCP 37/0, Agent Runtime 95/0, Engine 696/0,
  Calls 81/0, Gateway 413/1, Artifacts 20/0, Persistence 99/0 and Console 106/0.
- The sole failure repeats the previously recorded native WebRTC test
  `human_transfer_webrtc_test.exs:214`, assertion at line 355: the listener decoder reports
  `text: "E "`, `total_windows: 25`, `current_windows: 23`, `current_kind: :silence` and
  no remaining marks instead of the expected final `"E"` event. This exact failure occurred
  before the Zenmux change and already reproduced in unchanged isolation. Its cause remains
  unresolved; no additional isolation run, timeout change or weakened assertion is warranted
  by this repeat. The final milestone umbrella gate remains open.
- Logs: `tmp/zenmux-final-root-{format,compile,credo,test,unused}.log` (untracked verification
  output). Final independent fixture/documentation re-review found no blockers; the real
  application credential key and endpoint settings are seeded/restored separately.

## Checkpoint acceptance

- Final independent GPT 6 Astra xhigh gate review confirmed checkpoint 5's own exit is satisfied:
  DB-selected credentials, malformed/mixed input rejection, actual request and routing preservation,
  no ambient fallback and setup documentation. Earlier Google/Deepgram evidence remains valid;
  carrier readers remain owned by checkpoints 3 and 4.
- The common root gates apply to milestone acceptance. The repeated native Morse failure leaves
  that gate and the whole milestone unchecked; it does not create another audio project within
  checkpoint 5. No native implementation/assertion change or full-suite success is claimed.
- Progress is now **3 of 7 complete** (1, 2, 5), **2 partial** (3, 7), **2 not started** (4, 6).
  This replaces the implementation commit's provisional partial status after the complete root
  result and independent gate review; the remaining work and unresolved suite failure are explicit.
