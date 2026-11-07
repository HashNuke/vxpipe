# Saved MCP telephony acceptance

T7 acceptance through saved PostgreSQL connection records, published call specs,
real managed phone admission and the existing local carrier/media fixtures.
Carrier commands and speech-provider wires use synthetic test values; the MCP
client performs actual loopback HTTP. No live provider credentials are read and
no real phone numbers are dialed.

The existing Gateway phone harness starts from a hand-built PreparedCall, so it
cannot establish the saved publication/preparation contract. Compose the Console
saved-MCP fixture with persisted native credentials and telephony service records,
then use the public incoming webhook and outgoing call API. Keep readiness and
tool completion assertions explicit; do not substitute direct IntegrationOwner
execution for admitted phone-room behavior.


## Fixture integration and evidence

- Both managed routes use encrypted native/provider and MCP records, actual spec
  publication, Calls preparation and Gateway admission. The stored call asserts
  managed cleanup is required. Signed incoming and outgoing carrier events use
  the normal Telnyx verifier and decoder; only carrier commands are synthetic.
- The legacy fixture adapts the current carrier lifecycle to the public
  `CallAdmission.start_incoming/3` entry. It observes that entry explicitly, starts
  without an admission token, delegates persistence/media operations and asserts
  the stored call is not marked for managed cleanup. This is a compatibility-host
  acceptance case, not a new production legacy HTTP route.
- Initial fixture runs exposed missing test configuration: STT media-ingress
  bounds, TTS request capacity, the supported Flux test voice and required end-of-
  turn trigger. Incoming records become running after the answered event. Carrier
  audio must wait for the actual admitted room's input gate to open; observing
  transport creation alone is insufficient. Corrected those fixture assumptions.
- All three cases now pass. Each observes actual carrier Opus bytes entering the
  STT wire, a model-selected authenticated MCP tools/call, the exact successful
  result and five carrier audio frames for each controlled 100 ms TTS utterance.
  Console's authenticated CSRF disconnect then blocks a second model-selected tool
  without another tools/call. The same stored room/incarnation remains running and
  response audio still reaches its original phone socket.
- Model/public responses and persisted plans exclude the synthetic MCP/native
  secret markers and MCP endpoint. This adds acceptance for existing production
  behavior; no implementation change or fabricated red test is needed.
- Format, warnings-as-errors compile, strict Credo and unused-dependency checks pass.
  At this stage combined acceptance, full umbrella tests and adversarial review
  had not yet completed. No UI or source-cutover/speech-state-machine source changed,
  so rendered UI and Lean reruns do not apply to this checkpoint.


## Independent adversarial review fixes

The initial three-route green run was insufficient for teardown evidence. Review
found that closing the room/client without a carrier-ended event could leave a
managed cleanup tracker retaining the sandbox context. The normal path now sends
an exactly correlated, signed hangup and waits for the room, socket, carrier leg
and managed tracker to terminate. Managed records must persist ended state with
completion at or after the archived ended timestamp. Failure cleanup explicitly terminates this
test's tracker after attempting room/client cleanup; socket fixtures do not restart.

Review also required a second no-tools/call assertion after final speech and
observed cleanup, plus privacy checks on every decoded carrier output frame before
filtering by event. Both are added. These are acceptance-fixture fixes; the review
found no production behavior defect. The strengthened rerun and further fixture corrections are recorded below.


The stricter rerun also required the real EctoStorage archive writer: without it,
carrier cleanup can finish while the durable call still lacks terminal archive
evidence. Enabled the same archive composition as managed production acceptance.
Carrier hangup preserves the archive event's ended_at, while cleanup completes
later; unlike API-requested hangup, those timestamps need not be equal. The tests
assert their ordering. All three routes, including the legacy host, now wait for
persisted ended state and archive_stream_closed before releasing the sandbox,
checking every fetched fact for private markers. This avoids a writer outliving
its test's database ownership. All three strengthened cases pass and independent
adversarial source re-review is clean. The final combined saved-runtime suite
passes 20 tests with zero failures. Format, warnings compile, strict Credo and
unused-dependency checks pass on the frozen code. The final umbrella run with seed
397067 passes 4,987 tests with zero failures (218 excluded). It also verifies the
independently reviewed existing STT-test synchronization correction, which is a
separate maintenance checkpoint. No source-cutover or speech-state-machine source
changed. All 239 relative documentation links checked before final staging resolve.
