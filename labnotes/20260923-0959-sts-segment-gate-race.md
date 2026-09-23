# STS segment root-gate investigation

Post-`dc394717`, all four root static gates passed. The socket-backed root
test run (`ERL_FLAGS='+S 2' PGHOST=/var/run/postgresql mix test --seed 0`)
reported one failure among 1,501 Call Engine tests, in
`SpeechToSpeechOutputSTTTest`'s multi-segment finite-input case at the final
`GenServer.call(recognizer, {:emit, :input_finished, []})` assertion. The
low-volume output filter captured the failing source line but omitted the
unmatched result; do not infer its value. The run proceeded into Gateway and
was explicitly stopped after the Call Engine summary to investigate. The
Gateway portion and full root result are not gate evidence.

Focused reproduction attempts after the run: the exact case passed 1/0; its
29-test file passed 29/0; 30 exact-case repeats passed. A 99-test adjacent
group (`speech_to_speech_output_stt_test`, `speech_to_speech_test`,
`sts_transcript_settlement_test`, `sts_output_test`) passed all ten seed-0
repetitions. This is an intermittent root-context failure, not yet a verified
runtime defect. No runtime or timeout change is justified by these results.
A subsequent complete Call Engine child run passed 1,501/0 (30 excluded), seed
0, with two schedulers. Next reproduce with captured full assertion output and
a controlled ordering before deciding whether the test or implementation needs
repair.
