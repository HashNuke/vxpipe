# Provider turn detection and contextual barge-in

Status: superseded as an implementation checklist, 2026-11-16. The user requested
one combined milestone. All pending scope and progress now belong to
[Voice agent turns, listening cues and spoken transcripts](voice-agent-turns-and-listening.md);
this file keeps its identity for existing links and historical evidence.

## Checkpoint mapping

| Former task group | Combined checkpoint owner |
| --- | --- |
| A/B — Profile research and turn completion | C first-profile endpoint behavior; F broader provider/latency coverage |
| C — Structured interruption and participant modes | C — Structured interruption and participant modes |
| D — CPU classifier in configured calls | D — CPU backchannel filter in configured calls |
| E — Broader providers, languages and latency | F — Telephone calls and validated language coverage |

Do not maintain a second pending checklist here or mark this reference file
implemented. The combined milestone contains the source coverage map, meaningful
checkpoint exits, prerequisites, tests and acceptance gates. The specification
sources remain authoritative for detailed contracts.

## Design review — separate from implementation

The earlier local review and task split were superseded by the requested
consolidation. See the combined milestone's design review for the independent
Astra xhigh coverage review and its resolutions. This move does not claim new
implementation, provider acceptance or deployment.

## Scoped checkpoint — remove Scribe's local endpoint wait

On 2026-11-14 the user requested only removal of the extra wait, deferring
barge-in. [Checkpoint evidence](../20261114-0215-provider-endpoint-wait.md)
records the narrow protocol investigation and verification.

- [x] Establish provider silence evidence separately from forced transcript
  commits, without selecting a different model or introducing local VAD.
- [x] Remove Scribe's 1.5-second transcript-settling timer. Request provider
  keepalives and finish immediately on an empty silence notification after
  committed text with no outstanding draft. Preserve local/manual endpoint
  waits and current barge-in behavior.
- [x] Prove the behavior red/green, including forced segments, retained drafts,
  repeated identical answers, missing evidence and duplicate silence events.
- [x] Complete live repeated/long/noisy input checks with optional VAD off/on,
  the full default suite and required root/Lean checks.

Verification: six live conversational cases pass, alongside all 5,314 default
tests (zero failures, 385 excluded), root static checks and Lean. Commit `cd4a2de2`
was deployed as a production release to `vxpipe.service` on 2026-11-14. Local and
public health checks pass, and all 1,779 project BEAM hashes match the release
build. This does not complete the whole milestone.

This uses provider-gap evidence, not semantic sentence completion. Provider
silence processing and keepalive cadence still contribute latency; this checkpoint
does not claim the one-second end-to-end target or the broader barge-in design.
