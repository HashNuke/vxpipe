# STS compiled transfers

Date: 2026-09-26. Starting revision: `68fa5a56`.

## Work and decisions

- Read Package 8 and the E acceptance checklist. The room-owned lifecycle
  tests already prove the fake GPT-Live socket's hold acknowledgement, release
  on the same socket, and provider/capability teardown. The missing proof was
  orchestration from a compiled room; added it with Morse duplex.
- The first success test expected `RoomAuthority.transfer/1` to stop the
  source immediately. The transfer commits the destination first; the source
  tool completion then sends `:vxpipe_platform_effect` to perform teardown.
  The test now exercises both steps and monitors the provider and capability
  exits.
- The first failure test used the default fixture, which accepted
  `test:unavailable`. Switched to the existing selective model fixture so
  destination preparation really fails. The test checks that the original
  provider remains bound, is unheld, and accepts new text.
- An attempted compiled GPT-Live fake socket case was rejected during plan
  validation because public runtime provider settings intentionally accept
  only `enabled`. Fake transport injection remains confined to the approved
  fake-socket capability and room-owned lifecycle tests. No runtime settings
  contract was changed to serve the test.

## Verification

- Compiled Morse transfer file: two tests, zero failures.
- Combined Package 8 capability and room matrix: 59 tests, zero failures.
- Format, warnings-as-errors compile, strict Credo (1,135 files, zero issues),
  unused dependency, and Lean verification passed.
- The umbrella suite passed 2,855 tests, zero failures and 59 tagged
  exclusions. CallEngine passed 1,664 tests and Gateway passed 519 tests.
- A post-suite audit found the compiled STS provider advertises `transfer`
  while `SpeechToSpeech.Tools` submits only host tools. The direct room
  transfer cases above do not cover that provider-originated tool path.
  Amendment 2 records the gap; E remains unchecked pending a red-green fix.
- Added a provider-originated transfer call to the compiled Morse room test.
  It failed red because `ToolCallCompleted` never arrived. The STS executor
  now builds a room-owned context with the caller identity and current STS
  capability and submits the allowlisted transfer binding through the normal
  invocation registry. `ParticipantTransfer.Request` uses that capability,
  while text-agent requests retain their existing coordinator lookup.
- The first green run published `ToolCallCompleted` but left the source
  provider alive. A committed transfer had already moved the caller, so the
  generic STS result path rejected the old connection as stale. The STS
  completion handler now sends the room platform effect for this successful
  outcome before that stale-connection check. Failure still returns a tool
  failure result to the provider and leaves the source session usable.
- The provider-originated success and destination-failure tests pass. The
  focused transfer, STS duplex, speech-to-speech, and agent transfer matrix
  passed 49 tests with zero failures. Format, warnings-as-errors compile,
  strict Credo, unused dependencies, and Lean verification passed. The full
  umbrella gate is running; Calls exposed an unrelated publication-worker
  monitor race recorded in `20260926-2309-publication-monitor-race.md`.
- An independent review found that the fake GPT-Live socket still lacked a
  provider-originated transfer proof through the compiled room. A private
  fake-wire injection before caller attachment now drives both committed and
  failed transfer cases. The failure case verifies `function_call_output` for
  the original call ID, `response.create`, release of the same provider, and
  fresh caller audio; the success case verifies provider and capability
  termination while RoomAuthority remains responsive.
- Teammate review iterations removed `Process.alive?/1` assertions and exact
  internal exit reasons. Two independent subagent reviews found no remaining
  concrete issue. The six focused transfer tests pass; the final root format,
  warnings-as-errors compile, strict Credo, unused-dependency and Lean checks
  pass. The first umbrella run exposed an unrelated STT test race; after its
  separate test-only correction, the final umbrella suite passed 2,859 tests
  with zero failures and 59 tagged exclusions. Package 8 E is checked.
