import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

const { openTransferConnection } = vi.hoisted(() => ({
  openTransferConnection: vi.fn(),
}));

vi.mock("./transferConnection", () => ({ openTransferConnection }));

import TransferPage from "./TransferPage";

afterEach(() => {
  cleanup();
  openTransferConnection.mockReset();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

test("explains the required setup when the transfer sample is disabled", async () => {
  const fetchMock = vi.fn().mockResolvedValue({ ok: false, status: 404 });
  vi.stubGlobal("fetch", fetchMock);
  render(<TransferPage />);

  fireEvent.click(screen.getByRole("button", { name: "Connect transfer desk" }));

  const alert = await screen.findByRole("alert");
  expect(alert).toHaveTextContent("The transfer sample is disabled.");
  expect(alert).toHaveTextContent("Restart bin/dev");
  expect(alert).not.toHaveTextContent("VXPIPE_DATABASE_URL");
  expect(alert).not.toHaveTextContent("Request a human transfer");
  expect(openTransferConnection).not.toHaveBeenCalled();
  expect(fetchMock).toHaveBeenCalledOnce();
});

test("connects the latest sample destination and activates only after explicit acceptance", async () => {
  const accept = vi.fn();
  const close = vi.fn();
  openTransferConnection.mockResolvedValue({ accept, close });

  const fetchMock = vi
    .fn()
    .mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        tenant_key: "BBBBBBBBBBBBBBBB",
        participant_key: "20000000-0000-4000-8000-000000000006",
        call_id: "30000000-0000-4000-8000-000000000003",
        join_token: {
          token: "vxj_browser-transfer-token",
          expires_at: "2026-09-11T08:35:00Z",
        },
      }),
    })
    .mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        call: {
          call_id: "30000000-0000-4000-8000-000000000003",
          state: "running",
          started_at: "2026-09-11T08:30:00Z",
        },
        participant: {
          participant_id: "part_support",
          role: "human",
          room_id: "room_demo",
          incarnation_id: "rinc_demo",
          state: "pending_transfer",
        },
        session: {
          session_id: "sess_support",
          expires_at: "2026-09-11T08:35:00Z",
          transport: {
            type: "smallwebrtc",
            endpoint: "/api/rtvi/offer",
            request_data: { session_id: "sess_support" },
          },
        },
      }),
    });

  vi.stubGlobal("fetch", fetchMock);
  render(<TransferPage />);

  fireEvent.click(screen.getByRole("button", { name: "Connect transfer desk" }));

  await vi.waitFor(() => expect(openTransferConnection).toHaveBeenCalledOnce());
  expect(fetchMock).toHaveBeenNthCalledWith(1, "/sample/transfers", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({}),
  });
  expect(fetchMock).toHaveBeenNthCalledWith(
    2,
    "/api/tenants/BBBBBBBBBBBBBBBB/calls/30000000-0000-4000-8000-000000000003/participants/20000000-0000-4000-8000-000000000006/sessions",
    {
      method: "POST",
      headers: {
        authorization: "Bearer vxj_browser-transfer-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({}),
    },
  );

  const callbacks = openTransferConnection.mock.calls[0][1];

  act(() => {
    callbacks.onControl({
      type: "preparation",
      attemptId: "xfer_demo",
      participantId: "part_support",
    });
  });

  fireEvent.click(screen.getByRole("button", { name: "Accept transfer" }));
  expect(accept).toHaveBeenCalledWith("xfer_demo");

  act(() => {
    callbacks.onControl({ type: "active", attemptId: "xfer_demo" });
  });

  expect(screen.getByRole("status")).toHaveTextContent("Main room active");
  expect(JSON.stringify(fetchMock.mock.calls)).not.toContain("vxp_");
});
