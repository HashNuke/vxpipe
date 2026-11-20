# Scribe receipt cursor

Proved a receive/send overlap in the existing synchronous transport boundary. ContinuousSTT can be blocked waiting for an audio-write reply while ScribeSocket receives and stamps an inbound event, queues that event to ContinuousSTT, then sends the newer audio and replies. ContinuousSTT resumes its audio handler and increments accepted_samples before handling the older receipt. The old landmark therefore paired a pre-write receipt timestamp with a post-write sample cursor.

Added optional successful-send callback metadata to Speech.Socket, used only by ScribeSocket. ScribeSocket counts audio samples after the socket write succeeds and snapshots that count with each diagnostic inbound receipt. ContinuousSTT uses that frozen cursor for the corresponding provider landmark. Adapter-emission timestamps retain their own current cursor. Existing plain transports, pair receipts and unrelated providers retain their current behavior. Failed/not-ready/retiring sends do not advance the cursor; neither keepalives nor manual commits count as audio.

The browser test wrapper must initialize sent_samples to zero and delegate handle_sent/2 to ScribeSocket; root owns that wrapper update. No packet storage schema changes or sample-frontier rounding were needed.

Verification:

- Red: ScribeTimingTest 19 tests, one expected failure. Controlled transport delivered inbound receipt before replying to a second 320-sample write: receipt incorrectly reported 640 instead of 320.
- Green: timing/profile tests, 25 passed (4 integration-tagged exclusions), seed 489965.
- Green: explicit focused local-loopback socket lane plus timing tests, 26 passed, seed 845563. Confirms real socket send tracking, receipt snapshot and no cursor advance after retirement.
- Changed files formatted and diff whitespace check clean.

Local loopback tests use the synthetic WebSocket server only. No live provider requests, Telnyx calls, inference model tests or full-suite run were performed.

## Review correction: optional callback compatibility

The existing uninstrumented ScribeEvidenceSocket wrapper delegates audio sends but does not implement handle_sent/2. A new local-loopback regression reproduced UndefinedFunctionError on its first successful write (4 tests, one expected failure). Made dispatch genuinely optional with function_exported?/3, retaining callback state when absent. Instrumented Scribe sockets still execute their send counter callback; wrappers without diagnostics retain their historical behavior. The first combined rerun found a race in the new retirement assertion: a real peer can complete close before the assertion, legitimately returning connection_lost. Replaced that assertion with the deterministic retiring-state send boundary, which must return the unchanged state without invoking the optional counter callback. Final rerun recorded below.

Final focused local-loopback/socket/timing verification: 27 tests passed, seed 903439. Log: `/tmp/vxpipe-optional-callback-green.log`.
