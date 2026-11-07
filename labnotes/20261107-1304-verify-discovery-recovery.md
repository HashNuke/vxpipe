# Verify discovery recovery

Complete the remaining custom discovery browser states with controlled real HTTP
peers: transiently unavailable authorization metadata, multiple issuers with one
unavailable choice, and metadata lacking the required S256 capability. Preserve
credentialless discovery: no registration, token request or MCP invocation.

Write focused protocol regressions before adding the startup scenarios. Then use
the authenticated Console to verify retry, issuer selection and explicit unsupported
recovery; keep broader listed/outage and release gates separate. No speech or
source-cutover state-machine change is involved.

Three tests fail against the missing scenarios, then all 39 combined
peer/consent/OAuth/renewal cases pass. Independent adversarial source review is
clean. The partial failure counter is consumed atomically; do not probe its metadata
before the browser, since this scenario fails once per startup.

Authenticated desktop Chrome shows the partial-discovery notice and Retry discovery
with no connected record. Choosing Bearer manually before retry preserves that
choice when metadata recovers; discovery alone still leaves inventory empty.
Explicitly selecting CIMD then reaches real consent and a successful callback.
Saved testing returns HTTP 200, mobile Tools shows list_events, and disconnect
empties inventory. The complete mobile Tools capture and desktop partial-state
capture were visually inspected. A malformed shell-quoted CSS wait was cancelled;
selector waits use JSON stdin so attribute quotes are preserved.

Multiple-issuer discovery initially requires explicit selection. Selecting the
unavailable issuer produces a partial state while keeping that issuer selected;
the mobile form shows retry, selection and footer controls. Selecting the working
issuer recovers and prefills CIMD, then real consent returns to the inventory.
Saved testing returns HTTP 200, mobile Tools shows list_events and disconnect
empties inventory for the recovered multi-issuer connection as well.

Unsupported discovery stays explicit, selects no method automatically and leaves
Connect disabled until a method is selected. Manually selecting CIMD and submitting
makes no further OAuth request and creates no connected record. This exposed a
misleading validation message asking the user to discover again after unsupported
metadata was already known. A focused component regression fails on that message,
then passes after the shared OAuth validation reports the existing unsupported
security explanation. The eight focused form/dialog cases pass; TypeScript, the
actual isolated asset build, and all 1,064 frontend tests pass.

The corrected error is rendered and visually inspected at 390×844 and 1280×900;
controls stay visible and the message wraps within the form. The dedicated browser
is closed with private saved state, and all owned peer processes are stopped.
This is a bounded copy correction, preserving the existing visual system. No
physical-device or production outbound DNS/TLS claim is made.


Independent adversarial re-review of the fixture, one-line UI correction,
regression, documentation and four rendered captures found no actionable findings.
The final static rerun passes format, compilation with warnings as errors, strict
Credo and unused-dependency validation. The unchanged Elixir fixture source's
umbrella run also passes: 4,991 tests, zero failures, 253 excluded, seed 390973.
All five root gates therefore pass; the UI correction has the separate final
frontend/type/build and rendered evidence above. Lean is not applicable.
