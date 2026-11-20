# Primary metrics presentation

## Scope and decision

Audit the existing persisted/API/UI acceptance for both primary measurements:
human speech end to STT turn-end receipt, and human onset to acknowledged server
egress stop. No runtime change or redundant acceptance test is needed. Split the
milestone's combined checkbox into completed offline presentation verification and
still-pending live acceptance. This preserves the live requirement without
claiming that deterministic configured fixtures or Storybook exercise real audio
accuracy or provider behavior.

## Evidence map

- **Durability:** `apps/vxpipe_persistence/test/vxpipe/persistence/latency_store_test.exs`,
  “barge-in evidence survives durable revisions while legacy absence remains nil,”
  roundtrips the complete turn alongside existing endpointing landmarks. The
  fixture's acoustic end and provider receipt preserve the derived endpointing
  duration. Available and unavailable barge-in revisions, explicit reasons,
  omitted-entry counts, legacy absence and stale-revision rejection are checked.
  The [storage/API checkpoint](20261120-0149-barge-storage-api.md) records 19/19
  Persistence tests after the expected red test.
- **Authorized API:** `apps/vxpipe_console/test/vxpipe/console/call_latency_endpoint_test.exs`
  checks microsecond precision, null stages and clock provenance; its barge-in
  test verifies exact output identity/evidence through both authorized aliases
  with private no-store headers. Existing authentication checks remain green.
  The same checkpoint records 11/11 Console endpoint tests.
- **Wire parsing:** `apps/vxpipe_console/assets/src/callLatencyApi.test.ts`
  verifies late confirmation separately from onset, nil/legacy absence,
  unavailable reasons and rejection of fabricated or contradictory durations.
  The [UI checkpoint](20261120-0149-vad-barge-ui.md) records 13/13 parser tests.
- **Primary presentation and revisions:**
  `packages/react/test/latencyDiagnostics.test.tsx` verifies both primary column
  labels, millisecond formatting, collapsed defaults, interrupted-output identity
  and late evidence updates without fabricated zero values. Positive sub-ms
  values display `<1 ms`, distinct from exact zero and unavailable data.
  The UI checkpoint records 37/37 component tests after four expected precision
  regression failures; independent Astra re-review passed.
- **Rendered example:** the same UI checkpoint records Chromium desktop
  1440×1000 and mobile 390×844 inspections, including shared and admin hosts.
  Available examples display 425 ms endpointing and 160 ms barge-in delay;
  ambiguous onset and unavailable stop remain distinct. Refresh resolves late
  evidence while preserving expansion. A separate precision fixture renders
  20 ms onset, 35 ms stop, 15 ms duration and `<1 ms` uncertainty. These are
  previously inspected synthetic examples, not a new browser pass in this audit.

## Remaining live requirement

`apps/vxpipe_console/test/integration/elevenlabs_configured_room_test.exs` currently
checks live configured Scribe transcription/recognizer behavior, but has no
latency, diagnostic or barge-in assertions. It cannot establish that live
acceptance exercises both measurements. That clause remains unchecked in the
milestone and must be satisfied by the later live acceptance work. No live tests,
real Telnyx numbers, provider credentials, native accuracy runs or deployment were
used in this audit.

## Verification

Read the source tests and the linked checkpoint evidence rather than rerunning
already-green suites for a documentation-only tracking change. No production or
test files changed. `git diff --check` passes. No Mix process was started; the
shared Mix lane is released to the parent.
