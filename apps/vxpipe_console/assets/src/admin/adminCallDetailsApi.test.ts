import { expect, test } from "vitest";

import { parseAdminCallDetails } from "./adminCallDetailsApi";

export const adminCallDetailsResponse = (state: "running" | "ended" = "running") => ({
  tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
  definition: { id: "delivery-rescheduling", name: "Delivery rescheduling" },
  definition_revision: 3,
  inspection: {
    schema_version: 1,
    call: {
      id: "call-public-id",
      revision: state === "running" ? 3 : 4,
      state,
      created_at: "2026-09-17T02:20:00Z",
      started_at: "2026-09-17T02:20:03Z",
      ended_at: state === "ended" ? "2026-09-17T02:22:17Z" : null,
      terminal_reason: state === "ended" ? "completed" : null,
      duration_ms: state === "ended" ? 134_000 : null,
    },
    incarnation: { room_id: "room-1", incarnation_id: "incarnation-1" },
    participants: [],
    timeline: [],
    variables: { state: "unavailable", reason: "not-captured" },
    metrics: [],
    metrics_availability: { state: "unavailable", reason: "not-loaded" },
    completeness: {
      state: state === "ended" ? "complete" : "unconfirmed",
      missing_sequence_count: 0,
      dropped_live_records: 0,
    },
  },
});

test("validates call details context and inspection snapshot", () => {
  const parsed = parseAdminCallDetails(adminCallDetailsResponse());

  expect(parsed.tenant).toEqual({ key: "AAAAAAAAAAAAAAAA", name: "Example tenant" });
  expect(parsed.definition).toEqual({
    id: "delivery-rescheduling",
    name: "Delivery rescheduling",
  });
  expect(parsed.definitionRevision).toBe(3);
  expect(parsed.snapshot.call.id).toBe("call-public-id");
  expect(parsed.snapshot.completeness.state).toBe("unconfirmed");
});

test("rejects malformed context and inspection data", () => {
  const valid = adminCallDetailsResponse();

  expect(() => parseAdminCallDetails({ ...valid, definition_revision: 0 })).toThrow(
    "Invalid admin call details response",
  );
  expect(() =>
    parseAdminCallDetails({
      ...valid,
      inspection: {
        ...valid.inspection,
        call: { ...valid.inspection.call, state: "administrative" },
      },
    }),
  ).toThrow();
});
