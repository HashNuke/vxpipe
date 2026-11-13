# Receptionist startup failure

- Telnyx delivered the incoming event to the correct tenant route. Vxpipe sent a
  hangup before answering; its persisted call had `room_start_failed`.
- The running QA container belongs to `vxpipe.service`. Production config leaves
  STT and TTS registries empty, while development enables the implemented adapters.
  A complete-runtime probe rejects the caller's ElevenLabs STT at plan validation.
- An earlier standalone probe omitted runtime dependencies and falsely rejected
  the Google model catalog. Repeating with the call-engine dependencies loaded
  isolated the actual missing speech registration.
- The initial repair added a production receptionist regression and moved shared
  provider configuration out of development; the cleanup below supersedes it.
- User authorized code changes, redeployment, a TLS SIP call to the configured
  receptionist, and a push notification once the call stays connected. Voice
  quality and conversation verification are outside this acceptance check.
- Do not read environment files or expose credentials.

## Verification and deployment

- The production regression failed on the caller's STT selection before the fix
  and passed with the shared adapter configuration.
- The interim configuration lived in `config/speech.exs`, imported by development
  and production. Test configuration retains its explicit adapter registration.
  Putting enabled adapters in the base config initially broke the existing
  unavailable-adapter contract, so that broader approach was discarded.
- A separate runtime probe using the saved plan and configured credential source
  passes both plan validation and provider resolution with the corrected adapters.
- Installed SIPp and authenticated over TLS using the existing credential
  connection. A baseline call reproduced the pre-answer failure and persisted
  `room_start_failed`. Temporary SIP credentials and client keys are removed by
  the test harness; only a sanitized result is retained outside the repository.
- Other editor work appeared concurrently in this worktree. Build the release
  from a clean source snapshot plus this task's configuration changes, using the
  existing dependencies, so unrelated in-progress editor edits are preserved.
- The first broad test run used the discarded base configuration and was stopped
  after it reported the unavailable-adapter expectation and an STS transfer
  resumption failure. Run the required checks again with the database-owned implementation.

## Database-owned configuration cleanup

- The interim shared release config fixed the immediate call failure: a TLS SIP
  test was answered and stayed connected for 20 seconds before client hangup.
- The user clarified that release-level provider enablement must be removed,
  rather than made consistent across environments. The interim `speech.exs` file
  is therefore removed, along with base/dev provider maps and both runtime reads.
- `CapabilityCatalog` retains public selection/adapter validation. Internal queue
  and transport defaults move to `SpeechRuntimeOptions`; optional test transports
  are passed per call. Saved credentials remain the authorization source.
- Database-backed ElevenLabs tests failed before removing the registration gate
  (five failures) and passed afterwards (six tests). The production receptionist
  regression also passed without a speech config section.
- Removed the development config's obsolete inline call spec and automatic sample
  installer. The published database path and examples remain authoritative.
- Broad verification is in progress. Old tests asserting host enablement are being
  replaced with credential and supported-adapter assertions, and fake transports
  are now injected by a test-owned startup wrapper.

- Focused cleanup checks passed: 45 call-engine tests and 13 Console tests. The
  room-start regression deliberately poisons the retired app settings and still
  prepares its speech allocation.
- Broad checks reproduced the pre-existing STS transfer test race: the tool-failed
  event is published before its authority callback finishes hold settlement.
  Added a `:sys.get_state` acknowledgement before new test input; all six focused
  transfer tests pass. No speech state-machine transition changed.
- Built a production release and container successfully from a clean HEAD snapshot
  plus this task's changes. Verified the 11 changed production/configuration files
  match the worktree. Deployment awaits broad checks; rollback image retained.

- Full provider-source scan found no remaining application/environment reads in
  hosted speech adapters except the Morse API's private custom origin. That live
  endpoint is shared by discovery and transports and is retained/documented;
  removing it would break the separately deployed fixture service. No provider
  selection, model choice or enabled registry remains in application config.

## Final verification and live deployment

- Required formatting, compilation with warnings as errors, strict Credo and
  unused-dependency checks passed. All application suites pass after test repairs:
  engine 2,433 tests (100 excluded), Console 563 (121 excluded), Gateway 886
  (13 excluded), Persistence 532 (68 excluded), Calls 379, Artifacts 20, Identity
  101, MCP 222 (71 excluded), Providers 35 and Agent Runtime 108 (8 excluded).
- The umbrella run found the STS acknowledgement race, the retired demo-config
  test, and an existing Console lookup expectation omitting the configured Telnyx
  service. Removed the obsolete test and aligned the lookup assertion with the
  existing Calls contract; full engine and Console reruns passed afterwards.
- Deployed `vxpipe:db-speech-20261113` to `vxpipe.service` after confirming zero
  active carrier calls. Local and public health checks pass. The live release has
  no STT/TTS/STS application settings, and its database name matches the previous
  deployment. No database configuration or saved call spec was changed.
- The post-deployment TLS SIP call answered and remained connected for the planned
  20-second hold. SIPp exited successfully; Telnyx recorded 21 connected seconds,
  `NORMAL_CLEARING`, and zero active calls after the client hangup. This validates
  call survival, not audible conversation.
- The corresponding database call record still showed running after carrier
  termination, reproducing the separate post-hangup bookkeeping issue seen with
  the interim fix. Requested whole-call cleanup once via MCP; do not blindly retry
  an uncertain mutation. This is separate from provider startup/configuration.

- MCP cleanup did not return within the bounded observation period and was
  cancelled without retry. A read-only check still showed no hangup request or
  terminal timestamp. Carrier active-call count remained zero. Sent the user a
  push notification with the successful startup test and both remaining findings
  (live Morse endpoint wiring and stale post-hangup call bookkeeping).
