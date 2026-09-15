# Native readiness assertion

## Failure and decision

- Credential checkpoint 2's umbrella run failed only in the existing five-participant native
  WebRTC handoff test. It timed out on a 250 Hz caller-audio assertion immediately after removing
  a paused cue listener and fully reconnecting it. The unchanged case passed in isolation.
- Independent GPT 6 Astra xhigh source review identified an unsupported timing assumption:
  `HumanMediaHandoff.finish_cues/5` reconciles changed inventory and `prepare_release/4` can stop
  resumed waits immediately when the resulting graph is already ready. No minimum audible wait
  duration is promised at this point.
- Remove only that transient-tone assertion. Keep wait-tone verification after declaring an
  unattached listener, which supplies an explicit media-readiness blocker. Keep final cue/audio
  ordering, privacy and retained-player checks. No production behavior changes.
- The adoption gate's existing one-second automatic release can also interact with the removed
  two-second tone wait. Removing the unsupported assertion avoids that delay; no broader fixture
  or transfer/recovery feature work is included.
- The reviewer confirmed this minimal correction matches the intended contract. The scheduling
  explanation is supported by source, but the exact scheduling of the failed run was not traced.

## Verification

- Before correction, root run: 1,532 tests, 1 failure, 33 excluded, seed 235296. Format,
  warnings-as-errors compile and strict Credo passed; the driver stopped before the
  unused-dependency check.
- Unchanged isolated case: 1 test, 0 failures (67 excluded), 95.7 seconds. This demonstrated
  intermittency and did not establish a production defect.
- Corrected focused case: 1 test, 0 failures (67 excluded), seed 235296, 88.1 seconds. All five
  final root gates pass with the same seed and concurrency settings as the initial run:
  1,532 tests, 0 failures, 33 excluded, including 413 Gateway tests. This does not establish the
  cause of unrelated earlier native timing observations.

Run the focused case from `apps/vxpipe_gateway`:

```shell
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs:376 --preload-modules --max-requires 1 --max-cases 4 --seed 235296
```
