# STS held audio lane

The existing B native-coordination task requires caller STT to remain usable
when a selected STS route is intentionally retired. A focused Gateway test was
temporarily added to `sts_input_test.exs` using its real STT/STS ingress helpers.
It prepared both lanes, monitored and stopped the selected STS ingress, then
sent a valid Opus packet through `WebRTC.IncomingAudio.forward/4`. The owning
child command `ERL_FLAGS='+S 2' mix test
test/vxpipe/gateway/media/sts_input_test.exs:336 --seed 0` failed at the
expected boundary: delivery returned `{:unavailable, prepared_input}` despite
the live STT lane. The prepared input had advanced sequence 1. The test was
removed after the reproduction so the committed suite stays green; it must be
reintroduced as a red at the actual repair checkpoint.

A separate temporary test held the existing STS ingress without retiring it.
That case already returned `:ok` and delivered STT, so broad classification of
held input as a fatal error is not the problem. The retired case is different:
`STSInputHandle.push/2` reports `:speech_to_speech_unavailable`, and
`WebRTC.IncomingAudio` treats that as fatal to the Connection even after STT
delivery. The Gateway cannot infer from a missing STS ingress whether the room
intentionally retired the route or a required capability crashed. Do not make
all missing STS handles nonfatal. The pending room-authorized source-control
protocol must explicitly convey which STS lane is closed while maintaining
current-policy checks; then red/green this exact callback and a required-STS
failure countercase. No runtime code was changed.
