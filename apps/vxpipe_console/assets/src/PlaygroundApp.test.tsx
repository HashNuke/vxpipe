import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, expect, test, vi } from "vitest";

vi.mock("@pipecat-ai/voice-ui-kit", () => ({
  ConsoleTemplate: ({
    clientOptions,
    connectParams,
    titleText,
    transportType,
  }: {
    clientOptions?: {
      callbacks?: {
        onDisconnected?: () => void;
      };
    };
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
      <button type="button" onClick={() => clientOptions?.callbacks?.onDisconnected?.()}>
        Simulate client disconnect
      </button>
    </section>
  ),
}));

import PlaygroundApp from "./PlaygroundApp";

beforeEach(() => {
  window.history.replaceState({}, "", "/admin/samples/pipecat-console");
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

test("starts on the Pipecat Console room-creation page", () => {
  render(<PlaygroundApp />);

  expect(screen.getByRole("button", { name: "Create room" })).toBeInTheDocument();
  expect(screen.queryByRole("region", { name: "RTVI console" })).not.toBeInTheDocument();
});

test("keeps transfer acceptance on its own destination page", () => {
  window.history.replaceState({}, "", "/admin/samples/transfer");

  render(<PlaygroundApp />);

  expect(screen.getByRole("button", { name: "Connect transfer desk" })).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Create room" })).not.toBeInTheDocument();
  expect(screen.queryByRole("region", { name: "RTVI console" })).not.toBeInTheDocument();
});

test("creates a room when randomUUID is unavailable on an HTTP origin", async () => {
  vi.stubGlobal("crypto", {
    getRandomValues: vi.fn((bytes: Uint8Array) => {
      bytes.set(Array.from({ length: 16 }, (_value, index) => index));
      return bytes;
    }),
  });

  const fetchMock = vi
    .fn()
    .mockResolvedValueOnce({ ok: false, status: 404 })
    .mockResolvedValueOnce({ ok: false });
  vi.stubGlobal("fetch", fetchMock);

  render(<PlaygroundApp />);
  fireEvent.click(screen.getByRole("button", { name: "Create room" }));

  await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));

  expect(fetchMock).toHaveBeenNthCalledWith(1, "/admin/samples/calls", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({}),
  });

  expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/rooms", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ room_id: "room_00010203-0405-4607-8809-0a0b0c0d0e0f" }),
  });
});

test("enters the uncluttered Pipecat page after creating a room", async () => {
  vi.spyOn(globalThis.crypto, "randomUUID").mockReturnValue("00000000-0000-4000-8000-000000000001");

  const fetchMock = stubDurableAdmission();

  render(<PlaygroundApp />);
  fireEvent.click(screen.getByRole("button", { name: "Create room" }));

  const console = await screen.findByRole("region", { name: "RTVI console" });

  expect(console).toHaveTextContent("Vxpipe RTVI Playground");
  expect(console).toHaveAttribute("data-transport", "smallwebrtc");
  expect(console).toHaveAttribute("data-webrtc-url", "/api/rtvi/offer");
  expect(console).toHaveAttribute("data-session-id", "sess_demo");
  expect(screen.queryByRole("button", { name: "Create room" })).not.toBeInTheDocument();
  expect(screen.queryByText("room_demo")).not.toBeInTheDocument();
  expect(screen.queryByText("rinc_demo")).not.toBeInTheDocument();
  expect(fetchMock).toHaveBeenNthCalledWith(1, "/admin/samples/calls", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({}),
  });
  expect(fetchMock).toHaveBeenNthCalledWith(
    2,
    "/api/tenants/BBBBBBBBBBBBBBBB/calls/30000000-0000-4000-8000-000000000003/participants/20000000-0000-4000-8000-000000000002/sessions",
    {
      method: "POST",
      headers: {
        authorization: "Bearer vxj_browser-delegated-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({}),
    },
  );
  expect(JSON.stringify(fetchMock.mock.calls)).not.toContain("private-order-sentinel");
  expect(JSON.stringify(fetchMock.mock.calls)).not.toContain("vxp_");
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

test("returns to room creation after a connected client disconnects", async () => {
  stubDurableAdmission();

  render(<PlaygroundApp />);
  fireEvent.click(screen.getByRole("button", { name: "Create room" }));

  expect(await screen.findByRole("region", { name: "RTVI console" })).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Simulate client disconnect" }));

  expect(screen.getByRole("button", { name: "Create room" })).toBeInTheDocument();
  expect(screen.queryByRole("region", { name: "RTVI console" })).not.toBeInTheDocument();
});

test("keeps the database-free trusted room fallback", async () => {
  vi.spyOn(globalThis.crypto, "randomUUID").mockReturnValue("00000000-0000-4000-8000-000000000001");

  const fetchMock = vi
    .fn()
    .mockResolvedValueOnce({ ok: false, status: 404 })
    .mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        room: {
          room_id: "room_fallback",
          incarnation_id: "rinc_fallback",
          tenant_id: "tenant-development",
          created_by_actor_id: "actor-samples",
          lifecycle: "open",
        },
        participant: {
          participant_id: "part_fallback",
          role: "human",
          room_id: "room_fallback",
          incarnation_id: "rinc_fallback",
          state: "joined",
        },
        session: {
          session_id: "sess_fallback",
          expires_at: "2026-09-09T13:05:02.000000Z",
          transport: {
            type: "smallwebrtc",
            endpoint: "/api/rtvi/offer",
            request_data: { session_id: "sess_fallback" },
          },
        },
      }),
    });

  vi.stubGlobal("fetch", fetchMock);

  render(<PlaygroundApp />);
  fireEvent.click(screen.getByRole("button", { name: "Create room" }));

  const console = await screen.findByRole("region", { name: "RTVI console" });
  expect(console).toHaveAttribute("data-session-id", "sess_fallback");
  expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/rooms", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ room_id: "room_00000000-0000-4000-8000-000000000001" }),
  });
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

function stubDurableAdmission() {
  const fetchMock = vi
    .fn()
    .mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        tenant_key: "BBBBBBBBBBBBBBBB",
        participant_key: "20000000-0000-4000-8000-000000000002",
        call_id: "30000000-0000-4000-8000-000000000003",
        join_token: {
          token: "vxj_browser-delegated-token",
          expires_at: "2026-09-09T13:05:02.000000Z",
        },
      }),
    })
    .mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        call: {
          call_id: "30000000-0000-4000-8000-000000000003",
          state: "running",
          started_at: "2026-09-09T13:00:02.000000Z",
        },
        participant: {
          participant_id: "part_demo",
          role: "human",
          room_id: "room_demo",
          incarnation_id: "rinc_demo",
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
  return fetchMock;
}
