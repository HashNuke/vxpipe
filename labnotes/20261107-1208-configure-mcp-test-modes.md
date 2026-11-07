# Configure MCP test modes

Extend the existing real HTTP/TLS browser peer with startup-selected anonymous,
bearer, custom-header and Basic modes. Keep the existing CIMD/DCR behavior and
production ports unchanged. Generate fixture credentials per startup, write them
only to a private ignored file, and never include them in public peer metadata.

Acceptance requires actual ExMCP initialization/tool discovery with correct
credentials, rejection with absent/wrong credentials, and credentialless preflight
that only identifies anonymous access after a successful protocol check. Static
modes must not advertise or expose OAuth endpoints. Focused protocol tests precede
implementation; browser verification and independent review follow.

All four protocol cases failed first because the scenario module did not exist.
After implementation, all four pass alongside the existing CIMD/DCR, consent and
outbound OAuth checks (18 tests, zero failures). A formatter invocation initially
used root-relative paths from the child directory; it made no changes and was
corrected. The launcher now selects the scenario and writes generated credentials
only under the private ignored output directory. Rendered acceptance, independent
review and final root gates remain pending.

Independent adversarial review found two test-evidence issues. The shared parsing
refactor recorded RPC methods after authentication, weakening existing assertions
that no tools/call reached the peer. Three new negative assertions reproduced the
gap (received count 0 instead of 2). Restore pre-authentication received-method
counting without executing rejected requests. Also use incorrect credentials in
each method's own format: wrong bearer, wrong x-api-key, and correct Basic username
with a wrong password, retaining absent-credential cases. The static implementation
already compared exact values; the latter corrects evidence rather than a bypass.

Source re-review is clean after both fixes. All 18 combined tests also pass in the
main checkout; all five root gates are running. In the authenticated browser,
anonymous preflight selects No authentication only after real initialization.
Connect creates one resource; saved connection testing succeeds and the discovered
list_events tool renders without clipping at 390x844. Disconnect removes the
resource from the connected list before the next startup scenario. Screenshots
are held privately under /tmp and contain no credentials.

Bearer startup leaves discovery unresolved; it does not suggest anonymous access.
An incorrect token shows the credential retry error and no connected resource.
Using the generated private token connects exactly one bearer resource at
generation 1. Management hides saved values, saved testing succeeds, and the tool
list renders on mobile. Disconnect completes before the next scenario. File modes
were verified as 0700 for the fixture directory and 0600 for credentials.json;
peer.json contains only public resource, issuer, origin and mode fields.

Custom-header startup also leaves discovery unresolved. Its form has the expected
X-API-Key row and no empty additional-parameters section. A wrong value is rejected
without creating a connected resource; the generated value creates exactly one
headers resource at generation 1. Saved values stay undisplayed, saved testing
succeeds, and list_events renders on mobile. Disconnect removes it before the
Basic scenario. A browser CLI attempt to select through a semantic find command
was unsupported; using the inspected select reference worked without any app change.

Basic startup leaves discovery unresolved and exposes username/password without
an unsolicited X-API-Key row. On mobile, a correct fixture username with an
incorrect password receives create HTTP 503; the generated password then receives
HTTP 201 and produces exactly one Basic resource at generation 1. The initial
failure capture preceded the error render, so it is form-layout evidence only.
A subsequent explicit credential replacement with a wrong password renders the
retry error and receives HTTP 503 while preserving the original ID, namespace and
generation 1. Turning replacement off and testing saved credentials returns HTTP
200. The actual working credential remains undisplayed.

The final Basic tools view required keyboard navigation (focus Authentication,
ArrowRight, Enter). Repeated pointer activation instead dismissed the dialog.
Inspection shows the taller Authentication panel centered at top129 and the shorter
Tools panel at top232 in the 390x844 viewport; the previous Tools pointer coordinate
can fall outside the recentered panel. This suggests an interaction with Radix's
activation timing and SetupDialog's backdrop click handler, to be reproduced and
fixed in a separate UI checkpoint. The peer and saved API checks pass; pointer-tab
acceptance is not complete. One CLI text wait stalled on the dismissed view and
eventually returned a busy-daemon error; all related CLI commands are now terminal.
Keyboard navigation displays list_events correctly. The final screenshot was
inspected; captures of the dismissed view are not tool-list acceptance evidence.

All five root gates pass: formatting, warnings-as-errors compilation, strict Credo,
4,991 tests with zero failures and 241 excluded (seed 579799), and unused-dependency
verification. Independent source re-review and final exact-index adversarial review
are clean after the two fixture fixes. Keep remaining scenario and UI gates open.
