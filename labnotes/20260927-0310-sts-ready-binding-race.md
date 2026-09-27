# STS ready binding race

The root suite failed the provider-controlled source cutover assertion in
`STSTranscriptModesTest`. It also failed once when run alone. Temporary state
inspection on a later failure showed a held cutover with `stt_ready?: false`
and `fresh_stt?: false` even though the current STT capability had a ready
allocation generation different from the retired generation. No source arm
message followed.

The media policy can commit a prepared STT replacement before the room sees a
new `:connected` signal. The cutover previously trusted only a remembered
signal when processing the source hold receipt. A deterministic regression
test now clears that remembered marker after confirming the replacement
binding is ready, then requires the room to arm and reopen the exact source.
The focused test failed at the arm assertion before the fix.

`STSSourceCutover.bind_observed_source/1` now checks the active capability's
ready input binding when the hold receipt arrives. It binds the audio origin
only when the allocation generation differs from the retired one, and leaves
the input held if the binding is unavailable or still old. The focused
regression passed after the fix, including three additional focused runs, and
the entire transcript modes file passed (37 tests, zero failures).

Final verification: `mix format --check-formatted`, `mix compile
--warnings-as-errors`, `mix credo --strict`, `mix deps.unlock --check-unused`,
and `bin/verify-lean` passed from the umbrella root. The final default
`mix test` run passed 2,868 tests with zero failures. The first full run had
an unrelated `TTSCancellationTest` timing failure that passed in isolation;
the source-cutover failure then reproduced alone and was fixed here.
