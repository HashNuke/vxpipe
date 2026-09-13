# Media policy fixture timeouts

The required umbrella gates twice exposed scheduling-sensitive policy fixtures: the transcript
router's unrelated-revision test and the room mixer's policy/queued-media test returned
`{:error, :unavailable}` at their 100 ms acknowledgement deadline. Both test operational policy
semantics, not a 100 ms service-level guarantee; production acknowledgement deadlines are unchanged.

Use a bounded one-second fixture deadline for these policy calls. The same 18 focused room-mixer
and transcript-router tests pass. No runtime behavior or test assertions were changed. Full-root
verification is recorded after the current playback checkpoint gates finish.

The complete root gates passed: formatting, warnings-as-errors compilation, strict Credo,
1,053 umbrella tests with zero failures (15 integration tests excluded), and unused-dependency
checks. This fixture-only adjustment is committed separately from the playback implementation.
