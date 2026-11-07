# Observe held MCP responses

An independent audit compared the broad T7 acceptance item against the actual
saved-runtime and independent-node tests. The local web, managed incoming/outgoing
and legacy incoming phone paths, delayed transfers and runtime boundaries are
covered by the 20-case saved-runtime lane. Eleven independent-node cases separately
cover both grant types and token/transport lifecycle. The milestone permits these
lanes to proceed independently; it does not require each admitted call to run in a
two-node fixture. Cross-node browser callbacks and final release remain separate.

The audit found an evidence gap in two older held-response cases. Revocation could
return oauth_reconnect_required after a fixture timeout as well as after consuming
the explicitly released response. The node-crash case also sent release without
observing it, although its crash fence was independently established. Require the
existing correlated node_token_released and node_token_finished signals in both
cases. The latter indicates completion of the response-handling attempt, including
closed-client failure; it does not establish physical delivery to a dead client.

These are strengthened acceptance assertions against the existing fixture and
production behavior, with no runtime implementation change or artificial red phase.
All eleven runtime/lifecycle node cases pass with the stronger observations.
Update the stale broad T7 checkbox and saved-runtime summary to reflect the
separate proven lanes, retaining the remaining browser/callback/release gates.
Independent source re-review confirmed the assertions close the gap and found one
wording issue: completion means the response-handling attempt ended, and only the
named retirement cases consume the explicit acknowledgements. The T7 checklist now
uses that precise scope. All five root gates pass: formatting, warnings-as-errors
compilation, strict Credo, 4,991 tests with zero failures and 237 excluded
(seed 535581), and unused-dependency verification. Independent exact-index
adversarial review is clean after the wording correction.
