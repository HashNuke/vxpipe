# Configure OAuth test modes

Continue the approved integrations milestone with selectable real protocol peers
for the remaining custom OAuth browser checks. Provision own clients at startup
for public, Basic, POST and private-key JWT token authentication; machine clients
allow the three confidential methods. Protected DCR uses a fresh initial access
token. Keep credentials in the existing private ignored browser file and preserve
the real Console identity, CSRF, encrypted stores and compiled UI.

Nine focused cases fail before implementation because these scenarios are absent.
After adding provisioning and the registration guard, all nineteen peer/consent
cases pass. The broader protocol/renewal selection passes 36 tests with no failures.
The existing fixture's registration body was extracted without changing its
unprotected behavior. No production OAuth contracts or speech state machines change.

Independent adversarial source review found no actionable blockers in provisioning,
JWT verification, protected registration, protocol request counting or grant
restrictions. Documentation and rendered-evidence re-review also found no actionable findings.

Authenticated protected-DCR acceptance reused the previously disconnected Basic
endpoint. The initial create offered an explicit retained-record review before
protocol work. Selecting DCR in reconnect and submitting without the registration
token failed safely; entering the private startup token reached real consent and
restored the same ID/namespace at generation 4. Saved testing returned HTTP 200,
mobile Tools showed list_events, and disconnect emptied the connected inventory.

Own-client public, Basic, POST and private-key JWT clients pass real browser
consent, saved testing (HTTP 200), mobile Tools and disconnect. The three
confidential machine clients pass the same checks without a consent redirect;
discovery exposes only Client credentials and no callback field. Each fresh
endpoint connects at generation 1. The final own-client and machine private-key
mobile captures show the complete frame, list_events and persistent footer at
390×844. Some earlier captures show incomplete painted regions and are not used
as layout evidence. Creation and saved testing used the 1280×900 viewport.

The dedicated browser state is saved privately and the session closed. All owned
Console/peer processes are stopped, with the acceptance port confirmed idle. One
cleanup ownership check failed closed; the runner was changed to terminate its own
Popen child directly. No unverified listener was signalled.

Automation corrections: wait for actual visible text or the inspected aria-label
selector, rather than treating an accessible name as visible text. Snapshot refs
may include other attributes before ref. The private-key field is deliberately
read-only while masked; reveal before entering the PEM and hide before submission.
These required harness corrections, not product changes; failed attempts were not
counted as acceptance. Browser input and credentials remain private.


All five root gates pass on this checkpoint: formatting, warnings-as-errors
compilation, strict Credo, the umbrella suite (4,991 tests, zero failures,
250 excluded, seed 343039), and unused-dependency validation. The nine new
protocol cases are in the explicitly included integration lane (36 combined
focused cases passed). Production frontend source remains the already verified
49e26b09 dialog checkpoint; no new frontend or Lean state-machine change applies.
