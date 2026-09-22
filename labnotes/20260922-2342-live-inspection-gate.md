# Live inspection gate

The call-engine child suite ran 1,409 tests with one failure in
`LiveInspectionTest`'s post-buffer-crash participant snapshot. The exact test
failed again in isolation. A temporary pre-crash snapshot assertion also
failed with `:participant_not_found`, proving that the selected agent
participant had not been registered before fault injection. The inspection
buffer crash did not establish its absence; the test had never acknowledged
participant startup.

The test's intended boundary is that an inspection-buffer failure does not
tear down the live room. It now uses the public `CallEngine.monitor_room/3`
boundary before and after killing the buffer, checking the same incarnation
instead of assuming a participant authority exists. The focused test passes
1/0. No production runtime code changed. This is separate from the Google STS
audio-final checkpoint.

The entire three-test file passes 3/0; the full call-engine child suite passes
1,409/0 with 30 integration exclusions (seed 20131). Root umbrella gates
remain to be run after commit.
