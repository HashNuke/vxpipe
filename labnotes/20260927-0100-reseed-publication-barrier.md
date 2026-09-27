# Reseed publication barrier

The publication correction in `038d0bb8` removed rejected text from history,
but the provider could snapshot while a room acknowledgment was still queued
at the capability. Holding the capability with `:sys.suspend/1`, queuing a
published caller entry, and delivering an `expired` close reproduced this:
GPT-Live started the replacement before the capability resumed. The focused
test failed for that exact reason, then passed after the barrier.

The provider now requests a barrier through its speech channel. The channel
checks its bound producer and sends a marker to the allocation consumer. The
capability processes earlier room acknowledgments before the marker. For real
room calls it sends a second marker to the room, which responds only for its
current STS capability after earlier publication handlers finish. The room's
acknowledgments arrive at the capability before that response. Only then does
the capability release the provider to snapshot history. Both GPT-Live and
scripted Morse wait asynchronously, so the channel can still process the
capability's synchronous `append_history` requests. GPT-Live's existing
five-second reseed deadline covers the wait; Morse uses a four-second bound.

A second focused red test showed GPT-Live connecting before the room barrier
response. After the room hop, it passed. A room boundary test checks that
only the currently bound capability receives a barrier response. Direct
capability tests leave the room hop disabled because their owner is the test
process; the production RoomAuthority path enables it.

Root format, warnings-as-errors compile, strict Credo, unused-dependency and
Lean gates passed. The first full umbrella run ended nonzero: call-engine
reported seven failures under the full concurrent load. A combined focused
run had one failure in the provider-controlled STS source-arm test; that same
test passed alone. A captured child rerun reported exactly six failures, all
in direct GPT-Live provider tests whose test process was the allocation
consumer. They had not handled the new barrier marker, so the provider waited
and their immediate replacement assertions timed out. The tests now handle
the channel marker and release the provider as a consumer would. The updated
GPT-Live provider, fake-socket capability, Morse capability and room identity
tests pass together: 69 tests, zero failures. The next full umbrella run passed
2,867 tests, zero failures. Independent review then asked for a missing
barrier-withheld acceptance test. It first verified that no replacement socket
starts; after the five-second deadline it verified explicit `:reseed_failed`
and provider shutdown. That focused test passed.

Two later full runs including the new timeout test ended nonzero from
unrelated, load-sensitive fixture races: the STS overflow call was killed by
the capability's required teardown before replying, then an STT preparation
test sampled readiness before the channel's queued prepared event reached the
capability. Both test synchronizations were corrected and passed focused
verification; their separate labnotes record the detail. The final umbrella
rerun with both corrections passed 2,868 tests, zero failures, 61 tagged
exclusions. Root format, warnings-as-errors compile, strict Credo,
unused-dependency and Lean verification all passed afterward. The hosted
service and phone check was not run.
