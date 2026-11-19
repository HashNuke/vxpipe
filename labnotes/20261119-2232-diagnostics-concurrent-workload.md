# Concurrent diagnostic workload

## Change

Extended the existing external PCM smoke to concurrent rooms, each with one human
STT input. `--rooms N` accepts 1–16 and forwards the count explicitly through the
isolated launcher. The generator already supports staggered absolute schedules;
the configured fixture now routes packets by input index, provider receipts by
wire and response completion by room/source participant. Every input must deliver
all 64 frames byte-for-byte and complete two canonical turns. Each room retains
the complete six-event-per-turn oracle, expected diagnostic rows, optional
independent committed-row checks and teardown evidence. All rooms stop before
checking the shared collector/writer drain and admission release.

The concurrent fixture uses production collector/source capacity 16; inference
concurrency and queues remain unchanged. Connections have room-scoped supervised
identities only in the new concurrent scenario. Historical single-room fixtures
retain their established child ID and strict all-events trace collection.

For multiple inputs, the generator replaces the first 16-bit sample in each
512-sample frame with the input index plus one. The other 511 samples are unchanged;
the manifest declares `first-sample-index`. This gives each input distinct PCM
fingerprints, so actual Silero evidence from one source cannot satisfy another.
The receiving fixture checks each marker. Marker-only silence is excluded from
the speech-bearing inference proof. Single-input PCM is unchanged. These are
synthetic load fixtures, not labelled acoustic-accuracy audio.

## Verification and review

- An initial shell-only room setting did not survive sudo isolation and therefore
  ran the old one-input case. Its passing artifact is not concurrent evidence.
  The runner now forwards its explicit `--rooms` option and checks that every
  report identifies the requested room count and exactly 64 × N frames.
- The real two-room red run failed 4/4 on duplicate supervised connection IDs
  (`/tmp/vxpipe-concurrent-workload-two-red/`). The concurrent scenario now scopes
  those IDs by room. The first complete two-room run passed 4/4.
- Source-marker generation started red with an unexpected first sample. Python
  tests now pass 30/30, including unchanged single-input wrap behavior, staggered
  pacing, source-distinct payloads and rejection of a short single-input report
  for requested concurrency.
- The strengthened two-room run at `/tmp/vxpipe-concurrent-workload-marked/`
  passed 4/4 in 33.7 seconds with 128 frames per case, per-input actual inference
  evidence and committed rows. It precedes the final helper-review fixes below.
- Astra reproduced two shared-helper regressions. Default room filtering could
  hide an unexpected wrong-room event from historical single-room callers; a
  permanent regression failed before restoring default all-events collection.
  Concurrent smoke opts into room filtering and checks for global leftovers after
  every room's trace is verified. Root red evidence is
  `/tmp/vxpipe-concurrent-oracle-permanent-red.log`.
- Scoped connection IDs also broke the existing lifecycle cleanup by module ID.
  A permanent test using the real fixture failed with `{:error, :not_found}`
  (`/tmp/vxpipe-concurrent-connection-root-red.log`). The final implementation
  retains the old identity except in the explicitly concurrent scenario.

This is concurrent functional workload support. Full 20-second warm/cold paired
measurements, two STT humans in each room, latency and coverage budgets, and acoustic
accuracy remain open. No live providers, Telnyx calls or production deployment.

Final source review is clean. Root permanent helper regressions pass 2/2;
independent review's trace controls pass 4/4 and connection cleanup controls pass
2/2. Root format, warnings-as-errors compile, strict Credo and unused-dependency
checks pass. Final two-room evidence at `/tmp/vxpipe-concurrent-workload-final/`
passes all four modes with 128 delivered frames and four completed turns per
case. The run retained 340 resource samples, peak sampled RSS 809,492 KiB and
minimum available host memory 2,552,028 KiB. Generator p95 lateness was 0.063,
0.209, 0.223 and 0.423 ms in VAD/collection off/off, off/on, on/off, on/on order.
No abort, cleanup errors or retained database reservations remained.

The final single-room regression at
`/tmp/vxpipe-concurrent-workload-single-regression/` also passes 4/4, with unchanged
fixture encoding, 64 frames/two turns per case, committed rows and no unresolved
cleanup. These focused runs do not substitute for the final full milestone suite.

Final Astra artifact review is clean: both final runs match all eight source/model
hashes, requested counts, encoding, native affinity and database lifecycle records;
raw generator p95 recomputation confirms every case stayed within 2 ms.
