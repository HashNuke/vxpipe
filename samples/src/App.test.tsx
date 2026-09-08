import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

vi.mock("@pipecat-ai/voice-ui-kit", () => ({
  ConsoleTemplate: ({
    connectParams,
    titleText,
    transportType,
  }: {
    connectParams: {
      webrtcRequestParams?: {
        endpoint: string;
        requestData: { session_id: string };
      };
      webrtcUrl?: string;
    };
    titleText: string;
    transportType: string;
  }) => (
    <section
      aria-label="RTVI console"
      data-transport={transportType}
      data-webrtc-url={connectParams.webrtcRequestParams?.endpoint ?? connectParams.webrtcUrl}
      data-session-id={connectParams.webrtcRequestParams?.requestData.session_id}
    >
      {titleText}
    </section>
  ),
}));

import App from "./App";

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

test("starts on a dedicated room-creation page", () => {
  render(<App />);

  expect(screen.getByRole("button", { name: "Create room" })).toBeInTheDocument();
  expect(screen.queryByRole("region", { name: "RTVI console" })).not.toBeInTheDocument();
});

test("creates a room when randomUUID is unavailable on an HTTP origin", async () => {
  vi.stubGlobal("crypto", {
    getRandomValues: vi.fn((bytes: Uint8Array) => {
      bytes.set(Array.from({ length: 16 }, (_value, index) => index));
      return bytes;
    }),
  });

  const fetchMock = vi.fn().mockResolvedValue({ ok: false });
  vi.stubGlobal("fetch", fetchMock);

  render(<App />);
  fireEvent.click(screen.getByRole("button", { name: "Create room" }));

  await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));

  expect(fetchMock).toHaveBeenCalledWith("/api/rooms", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ room_id: "room_00010203-0405-4607-8809-0a0b0c0d0e0f" }),
  });
});

test("enters the uncluttered Pipecat page after creating a room", async () => {
  vi.spyOn(globalThis.crypto, "randomUUID").mockReturnValue("00000000-0000-4000-8000-000000000001");

  const fetchMock = vi
    .fn()
    .mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        room: {
          room_id: "room_demo",
          incarnation_id: "rinc_demo",
          tenant_id: "tenant-development",
          created_by_actor_id: "actor-samples",
          lifecycle: "open",
        },
        participant: {
          participant_id: "part_demo",
          role: "human",
          room_id: "room_demo",
          state: "joined",
        },
        session: {
          session_id: "sess_demo",
          expires_at: "2026-09-03T18:00:00Z",
          transport: {
            type: "smallwebrtc",
            endpoint: "/api/rtvi/offer",
            request_data: { session_id: "sess_demo" },
          },
        },
      }),
    });

  vi.stubGlobal("fetch", fetchMock);

  render(<App />);
  fireEvent.click(screen.getByRole("button", { name: "Create room" }));

  const console = await screen.findByRole("region", { name: "RTVI console" });

  expect(console).toHaveTextContent("Vxpipe RTVI Playground");
  expect(console).toHaveAttribute("data-transport", "smallwebrtc");
  expect(console).toHaveAttribute("data-webrtc-url", "/api/rtvi/offer");
  expect(console).toHaveAttribute("data-session-id", "sess_demo");
  expect(screen.queryByRole("button", { name: "Create room" })).not.toBeInTheDocument();
  expect(screen.queryByText("room_demo")).not.toBeInTheDocument();
  expect(screen.queryByText("rinc_demo")).not.toBeInTheDocument();
  expect(fetchMock).toHaveBeenCalledWith("/api/rooms", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ room_id: "room_00000000-0000-4000-8000-000000000001" }),
  });
  expect(fetchMock).toHaveBeenCalledTimes(1);
});
