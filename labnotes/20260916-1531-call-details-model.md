# Call details model

## 2026-09-16

- Reviewed the prototype `@vxpipe/core` contract. Its flat `CallSnapshot` currently combines
  durable call facts with microphone, speaker, device selection, and live commands. Whole arrays
  are replaced by Storybook fixtures.
- Reviewed existing Calls inspection contracts. Persisted history is cursor-paginated and carries
  archive completeness plus persisted variable revision. Live inspection is a bounded snapshot
  with call/room/incarnation identity, latest fact sequence, latest variable revision, and dropped
  and rejected record counts. Timeline entries already retain stable fact IDs, occurrence time,
  source sequence, correlation IDs, tool-call IDs, and variable revisions.
- Decided to normalize live and historical data through one Core call-details store, while keeping
  browser-local media and commands separate. React consumes derived immutable projections.
- Decided on stable entity IDs with monotonically increasing revisions, explicit tombstones,
  collection-specific updates, deterministic timeline order, and baseline refresh after a gap or
  changed incarnation. Raw RTVI receipts remain append-only even when they revise a semantic item.
- Historical adapters reuse authorized Calls inspection pagination and immutable call-details
  publications. Completeness, gaps, provenance, and unavailable/redacted values remain explicit.
- Recorded the contract and rejected alternatives in `docs/debug-console-call-details-model.md`
  and synchronized the debug-console milestone. Verification for this documentation checkpoint is
  Markdown/link inspection; reducer and rendered-equivalence tests belong to the implementation
  checkpoint.
- Clarified the source model after review: the authorized remote endpoint supplies baseline and
  accumulated history for ongoing as well as ended calls. RTVI is only the low-latency live edge
  when this browser is attached. An ongoing inspection can remain read-only without joining RTVI,
  and an ended inspection has no RTVI dependency.
- Chose an injected controller boundary: the Console host performs authorized fetches, supplies the
  initial call-details snapshot, and injects refresh/pagination callbacks. Core owns normalization
  and reconciliation; React renders the read-only store; neither reusable package knows endpoint
  URLs or authentication.
