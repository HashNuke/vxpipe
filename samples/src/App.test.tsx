import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

vi.mock("@pipecat-ai/voice-ui-kit", () => ({
  ConsoleTemplate: ({
    connectParams,
    titleText,
    transportType,
  }: {
    connectParams: { webrtcUrl: string };
    titleText: string;
    transportType: string;
  }) => (
    <section
      aria-label="RTVI console"
      data-transport={transportType}
      data-webrtc-url={connectParams.webrtcUrl}
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

test("enters the uncluttered Pipecat page after creating a room", async () => {
  vi.spyOn(globalThis.crypto, "randomUUID").mockReturnValue("00000000-0000-4000-8000-000000000001");

  const fetchMock = vi.fn().mockResolvedValue({
    ok: true,
    json: async () => ({
      room: {
        room_id: "room_demo",
        incarnation_id: "rinc_demo",
        tenant_id: "tenant-development",
        created_by_actor_id: "actor-samples",
        lifecycle: "open",
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
  expect(screen.queryByRole("button", { name: "Create room" })).not.toBeInTheDocument();
  expect(screen.queryByText("room_demo")).not.toBeInTheDocument();
  expect(screen.queryByText("rinc_demo")).not.toBeInTheDocument();
  expect(fetchMock).toHaveBeenCalledWith("/api/rooms", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ room_id: "room_00000000-0000-4000-8000-000000000001" }),
  });
});
