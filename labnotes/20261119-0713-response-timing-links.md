# Response timing links

The accepted room turn already owns the exact command/correlation identifiers used
by agent text and TTS requests. Keeping a constant-size diagnostic observation in
that existing turn avoids an additional registry and retires the association with
the normal turn lifecycle. Only successful room completion capture is propagated.

The first response regression failed on the missing response packet (7 tests, one
expected failure). The implementation records the first nonempty published text
only if transcript routing actually publishes to recipients, and the first authorized
playback-start acknowledgement accepted by the room. These are room observation
times in monotonic microseconds, not inference token latency or remote hearing.
Each bounded packet carries turn, command and output IDs, never response content.
The original timestamp survives worker forwarding. Repeated segments/acknowledgements
do not replace the first evidence; revoked capture does not prevent normal output.
No association is copied to an unrelated command or continuation.

Initial focused green:7/0. With empty-text and worker-forwarding coverage, the
broader run completed391 tests with one STS cutover timeout waiting for source arm.
That case passed in isolation (1/0); the same-seed broader rerun passed391/0.
No STS code was changed in response to this nonreproducing timeout.
Static root checks and Lean pass. Astra xhigh review is clean:27 independent
tests passed, covering publication filtering, exact identities, duplicates, saturation,
stale/deleted callbacks, payload bounds/copying and worker forwarding. Root tests
are still in progress. Automatic source attachment,
collector persistence and presentation remain separate unfinished milestone work.
