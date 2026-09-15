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
