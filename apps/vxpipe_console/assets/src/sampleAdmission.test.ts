import { expect, test } from "vitest";

import { isSessionResponse } from "./sampleAdmission";

test("rejects a participant session without its pinned room identity", () => {
  expect(
    isSessionResponse({
      participant: {
        incarnation_id: "rinc_demo",
        participant_id: "part_support",
        role: "human",
        state: "pending_transfer",
      },
      session: {
        session_id: "sess_support",
        expires_at: "2026-09-12T07:15:00Z",
        transport: {
          type: "smallwebrtc",
          endpoint: "/api/rtvi/offer",
          request_data: { session_id: "sess_support" },
        },
      },
    }),
  ).toBe(false);
});
