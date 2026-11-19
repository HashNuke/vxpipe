# Google renewal barrier

The full umbrella run reported the prepared-socket renewal test sending its next
frame on the original socket. Independent Astra xhigh review reproduced the exact
failure by suspending the replacement wire before its asynchronous setup delivery.
The provider barrier alone cannot wait for a message that the wire has not yet
forwarded. Production correctly keeps the old socket until replacement readiness.

The existing test now synchronizes the replacement wire and then the provider
before completing the old turn. This changes only test ordering. Independent red
probe1/1 expected failure; barrier and delayed-readiness probes plus original file
8/0. The repository test file passes6/0; Astra review of the final diff is clean.
Root static gates pass. The ongoing umbrella run predates this correction and also
has an unrelated Telnyx webhook authentication failure under investigation; it is
not passing acceptance evidence. A current-source root rerun remains required.
