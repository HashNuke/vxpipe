import { beforeEach, expect, test, vi } from "vitest";

const phoenix = vi.hoisted(() => {
  const connect = vi.fn();
  const liveSocket = vi.fn(function (
    this: { connect: typeof connect },
    path: string,
    socket: unknown,
    options: unknown,
  ) {
    Object.assign(this, { connect });
    return { connect, path, socket, options };
  });

  return {
    connect,
    liveSocket,
    socket: class TestSocket {},
  };
});

vi.mock("phoenix", () => ({ Socket: phoenix.socket }));
vi.mock("phoenix_live_view", () => ({ LiveSocket: phoenix.liveSocket }));

beforeEach(() => {
  vi.resetModules();
  phoenix.connect.mockClear();
  phoenix.liveSocket.mockClear();
  document.documentElement.innerHTML = `
    <head><meta name="csrf-token" content="csrf-test-token" /></head>
    <body></body>
  `;
  document.documentElement.setAttribute("phx-socket", "/admin/diagnostics/live");
});

test("connects the page-selected LiveView socket with shared hooks", async () => {
  await import("./live");
  document.dispatchEvent(new Event("DOMContentLoaded"));

  expect(phoenix.liveSocket).toHaveBeenCalledOnce();

  const [path, socket, options] = phoenix.liveSocket.mock.calls[0];

  expect(path).toBe("/admin/diagnostics/live");
  expect(socket).toBe(phoenix.socket);
  expect(options).toMatchObject({
    hooks: { MetricPulse: { updated: expect.any(Function) } },
    params: { _csrf_token: "csrf-test-token" },
  });
  expect(phoenix.connect).toHaveBeenCalledOnce();
  expect(window.liveSocket).toMatchObject({ path: "/admin/diagnostics/live" });
});
