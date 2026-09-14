# Startup readiness diagnostics

## Contract and initial evidence

The previous checkpoint completed fresh initial admission but startup observations still discarded
readiness blockers. Reuse CallLifecycle as the owner of total startup time and terminal state,
with bounded telemetry consumed by the existing Console reporter. There is no new UI component,
room process or user configuration. Each current worker contributes its actual blockers; lifecycle
aggregates a deduplicated closed category set and emits only changes. Late progress and repeated
completion/failure cannot publish another terminal setup result.

- Three lifecycle tests were red because no startup progress contract existed
  (`vxpipe-startup-diagnostics-red.log`). The lifecycle/event checks then passed nine tests.
- Four real-room tests were red because blocked model construction emitted no progress
  (`vxpipe-startup-diagnostics-room-red.log`). Observe the actual provider constructor through
  its initial lifecycle reference. Ready, failed, timeout and disconnect paths then pass alongside
  the existing lifecycle room tests (16 tests, zero failures).
- Opening and failed-resource paths explicitly report startup failure through the lifecycle before
  stopping. Readiness collectors contribute resource blocker kinds; removed connections cancel
  and clear their exact worker contribution. Existing handoff category normalization moved to one
  shared pure function, preserving the existing human-handoff categories.
- The reporter test was red with no startup projection. It now sanitizes before queue admission,
  retains only finite capability/outcome aggregates, and drops private payloads from queued events
  and snapshots (`vxpipe-startup-diagnostics-reporter-green.log`, nine tests).

## Speech-fixture detour

The independent speech/opening diagnostic check observed TTS and opening blockers but no STT
blocker. The embedded TestTransferConnection normal prepare_binding callback returned only its
connection resource, while its candidate callback included STT. An attempted normal-fixture change
prepared its selected ingress track and included speech resources. The full engine run then exposed
eight regressions: low-level speech-policy tests
intentionally prepare tracks later, and the Morse test requires its own negotiated format.
The generic embedded fixture cannot impose one early track on those distinct boundary tests.
Restore its original behavior; keep TTS/opening observation in the engine test and verify selected
STT through a native Gateway caller, whose adapter owns the actual negotiated track.
The native check passes with independent STT/TTS acknowledgements, continued received wait audio,
held RTVI text and one bot-ready/setup completion after both resources become ready.
An initial native line selection ran the preceding Morse check; the corrected location explicitly
ran the new diagnostic test (`vxpipe-startup-diagnostics-native.log`).
The fixture restoration also restores the distinct encoded-audio and recording track IDs used by
the opening tests. No production codec, track or provider policy changed.

## Additional observation boundaries

- Release-probe timeout/generation loss originally contributed no blocker while fresh preparation
  restarted. The release-readiness tests were red for the missing media category. The existing
  one-shot probe now reports its actual nonready resource through an optional callback; normal
  room collection clears this contribution after a fresh complete graph. Disconnect clears it
  when cancelling that exact release work.
- Candidate re-preparation can initially report several resources until their current probes
  return. The test requires the real media blocker after clearing previous observations; it does
  not require all unrelated asynchronous observations to have arrived first.
- A room with completed model preparation but no caller previously reported no blocker. Its new
  deadline test was red. Startup now reports missing connections as media, pending speech binding
  as STT, and typed preparation failures by their actual resource kind.
- Invalid/unknown kind values normalize to a fixed other category. The reporter's blocker counts
  count changed observations, not unique calls; terminal outcomes retain total setup duration and
  bounded final-blocker counts separately. Empty progress blockers never imply conversation ready.

## Umbrella observer isolation

After restoring the shared fixture, the next umbrella run passed its speech-policy and Morse tests
but one pre-existing coordinator telemetry test received an unrelated local-fixture model timeout.
That test owns a req_llm-labelled coordinator but attached a VM-wide unfiltered provider-failure
handler. Scope its three telemetry assertions to the emitting coordinator PID, without adding any
identity to public telemetry. The new lifecycle telemetry tests already use this same sender-local
filter. All 23 focused coordinator checks and the final root run pass after this fixture-only
correction.

## Design review

CallLifecycle already owns setup deadlines and terminal readiness, so it owns elapsed time and
source-specific blocker aggregation. A pure shared classifier keeps startup and handoff category
names consistent. The existing bounded Console reporter owns sanitization and aggregate storage.
This adds no process, dependency, configuration field, event-history store or UI component.
Creating a separate diagnostics coordinator would duplicate lifecycle state and introduce another
failure boundary. Resetting timing on retry would conceal total setup delay; retain the original
clock. Progress only reports unconfirmed readiness and never authorizes release. Abrupt process or
VM termination may prevent telemetry delivery; these observations are not a durable call ledger.

## Final verification and remaining scope

- Owning engine lifecycle, room, opening and telemetry files: 48 tests, zero failures
  (`vxpipe-startup-diagnostics-focused.log`).
- Existing Console reporter: nine tests, zero failures
  (`vxpipe-startup-diagnostics-reporter-green.log`).
- New native Gateway startup STT/TTS test: one test, zero failures, 26 other cases excluded by
  line selection (`vxpipe-startup-diagnostics-native.log`). The full root run then executes all
  27 cases in that file, plus the three existing native RTVI cases.
- Coordinator observer isolation: 23 tests, zero failures
  (`vxpipe-startup-diagnostics-coordinator.log`).
- Root `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix test --max-cases 4` and `mix deps.unlock --check-unused` all exit zero. Test seed 346041:
  **1,337 tests, zero failures, 15 integration exclusions**. Per application: MCP 37, agent runtime
  91, engine 623, Calls 81, Gateway 343, artifacts 19, persistence 49 and Console 94. Local evidence
  files use the `vxpipe-startup-diagnostics-gates-` prefix and include the result JSON and test log.

This completes the initial cleanup/diagnostics implementation task. **26 milestone checkpoint and
audit tasks remain**: human 7, AI 3, initial 2, phone 6, multiple listeners 6 and final audit 2.
All five full delivery slices remain unchecked. The initial slice still needs complete resource,
default/URL/nil and phone acceptance, including the previously recorded case where readiness is
lost after the initial fast path has skipped creating a wait player. No server restart or UI
inspection was needed for this backend checkpoint. Preserve the other agent's documentation-site
and visual-labnote changes. The remaining-task count and passing gates were sent through pushnotify.
