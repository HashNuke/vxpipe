# Diagnostics persistence wait

A bounded configured-file check failed two mixed-STT/STS cases with local Silero
off (seed 159480, /tmp/vxpipe-cold-fixture-check.log): a persisted row existed but
its later room_turn_completed landmark was still nil. The test waited for any row,
although provider and room completion are separate asynchronous writes.

The test now waits for the actual room completion landmark it asserts, retaining
all source, provider, response-absence and teardown assertions. This changes only
the observation boundary in the existing test, not production behavior or timeout.
Focused verification passes all four generated external/hybrid STS × local VAD
cases (seed 768411). The first location-filter attempt used a shifted line and
ran the preceding two tests; those passed but are not the regression evidence.
Independent Astra review found no issue with waiting for the asserted landmark.
No baseline claim is made.
