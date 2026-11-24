# Reversible Telnyx number assignments

The renamed QA application and the existing test application share the rocksalt
machine suffix. Read-only discovery found two active QA numbers. Preview,
borrow and restore reuse the live runner’s credentials and branch reservation.
Borrow records private number and application IDs before the first carrier
update. Restore preserves pre-existing test assignments and unrelated tags.

The shell carrier fixture initially failed on the missing command, then exposed
a cross-machine plan after the pool restriction was added. It covers a complete
round trip, retry, a third-party reassignment, and a renamed foreign-pool app.

A live borrow switched two numbers. The selected recovery test exited before
dialing because the public resolver returned no IPv4 Funnel relay. Restore
returned both numbers and a fresh inventory found both assigned to QA.

The second live attempt followed public Funnel readiness. All three relays
served health, the test dialed, and the test timed out waiting for Scribe to
start. Both numbers were restored and rediscovered on QA; the Funnel was
stopped. Handset audibility and signed callback completion remain unverified.

Following the operator's naming decision, the target applications are
`vxpipe-rocksalt-qa` and `vxpipe-rocksalt-test`. Borrowing, number discovery and
scoped cleanup require the machine and test-eligibility tags together. A
read-only plan could not find the new QA app name yet. No live migration was
performed.
