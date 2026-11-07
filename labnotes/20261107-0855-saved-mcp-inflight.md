# Saved MCP in-flight revocation acceptance

Continue T7/T8 acceptance after `c91c79dd`, which closes saved web boundary and
delayed-transfer checks. The milestone still requires telephony, independent-node,
authenticated rendered-browser and external-directory evidence.

## Contract and fixture design

An MCP request accepted by the remote server before disconnect cannot be retracted.
Its one result may complete in the admitted room. Disconnect must stop a later
submission, must not retry the already-submitted operation, and must not prompt the
caller to authorize OAuth. Preserve the same call incarnation and private projections.

Add an optional controlled invocation hold to the existing loopback wire fixture.
The fixture reports the exact handler, reference and JSON-RPC request ID only after
credential/header validation. Release must name that reference. Cancellation,
owner death and timeout return HTTP failure; no timing fallback synthesizes success.
Keep SSE open using the already-reviewed held-stream mode, so a reconnect cannot
confound this in-flight POST test.

The acceptance follows real saved publication and Console admission, sends input
through WebRTC, lets the scripted model select the tool, observes the authenticated
POST, disconnects through the session/CSRF-protected endpoint while the POST is held,
then releases the response. Assert its exact model outcome and peer output, try a
second invocation in the same room, observe terminal failure without another POST,
and close the call/client before releasing the SSE handler. Check for duplicate
requests and fixture timeouts after observed cleanup.

## Verification

The initial tagged acceptance passed without a production fix. Independent review
then identified an observation gap: checking only later `tools/call` messages would
miss unexpected initialization POSTs or SSE reconnects. The case now consumes the
exact original handshake/stream messages before disconnect and rejects any further
POST, GET, stream-open or held-invocation observation after cleanup, as well as
timeout reports. Its release acknowledgement cannot be produced by timeout/cancel.

All 17 saved-runtime/boundary/transfer/in-flight cases pass together. All five existing
Call Engine wire integration cases also pass with the extended fixture. All five
root gates pass: formatting, warnings-as-errors compilation, strict Credo, unused
dependencies and the umbrella suite (4,987 tests, zero failures, 215 excluded,
seed 957720). Independent adversarial source re-review is clean after strengthening
the observation boundary. No production behavior, UI or state machine changed;
no new rendered-browser or Lean acceptance is claimed.
