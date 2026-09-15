# Zenmux room startup

## Finding and scope

- Independent GPT 6 Astra xhigh review found that `PlanStartup.supported_model/1` still admits
  only Google and the fixture provider. `RoomSupervisor.start_call/2` invokes this gate before
  preparation, so the existing Zenmux integration cannot start an entry agent despite passing
  lower-level adapter construction tests.
- Correct the existing supported integration and test public room startup with an explicit
  named tenant Zenmux binding. This adds no provider or authentication method.
- Previous checkpoint 5 verification stopped below the failing boundary. Record this limitation
  and the focused red/green evidence with the correction.
- Kept the runtime tree unchanged until the telephony-guard umbrella run at `a21ba3f` finished.
  It completed 1,554 tests with the same native Morse failure and 33 exclusions; separate commit
  `6d779fb` records that evidence.

## Red/green evidence

- Added a public `CallEngine.start_call/2` regression using a compiled Zenmux entry agent with
  its existing native routing options and a named tenant credential. No external request is
  needed: the agent waits for input, and the test awaits the project's preparation acknowledgement.
- Red: one selected test failed with `unsupported_call_plan` at the receiver's model selection,
  before any room started. Green: adding Zenmux to the existing startup allowlist makes the same
  test pass. It observes the exact tenant/provider/name lookup and the prepared participant;
  the serialized plan contains no private marker. The test stops the room authority on exit.
- Broader affected group passes: 40 tests across definition-driven calls, model construction and
  inline activation, zero failures. The new test required routine formatting. Root format,
  warnings-as-errors compilation, strict Credo and unused-lock checks pass. Independent
  GPT 6 Astra xhigh implementation review found no blockers; a full umbrella regression is running.
- Review confirms the regression reaches public startup, waits for project-owned preparation and
  preserves the unsupported-provider rejection test. It uses no live provider request.
- Bounded review of the existing native failure establishes missing trailing audio as the symptom,
  not its cause. The test sends 48 frames; failures decode only 25–26 windows. A future diagnostic
  should compare sender/listener RTP sequence and timestamp ranges, sender lateness, and mixer/
  egress queue state for that utterance. No timeout or decoder-tolerance change is justified.
