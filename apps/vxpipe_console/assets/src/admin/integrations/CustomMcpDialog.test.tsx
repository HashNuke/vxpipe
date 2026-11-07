import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { CustomMcpDialog } from "./CustomMcpDialog";
afterEach(() => { cleanup(); vi.useRealTimers(); });
const endpoint = "https://mcp.example.test/mcp";
const defaults = { tenantKey: "tenant-a", csrfToken: "csrf", onClose: vi.fn(), onConnected: vi.fn(), onSessionExpired: vi.fn() };
const enter = (label: string, value: string) => fireEvent.change(screen.getByLabelText(label), { target: { value } });

test("unsupported OAuth security is shown without suggesting anonymous access", async () => {
  vi.useFakeTimers();
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => Response.json({ discovery: {
    ...JSON.parse(String(init?.body)), outcome: "unsupported_oauth", suggested_method: null,
  } }));
  render(<CustomMcpDialog {...defaults} fetchImpl={fetchImpl} />);
  enter("MCP server URL", endpoint);
  await act(async () => { await vi.advanceTimersByTimeAsync(400); });
  expect(screen.getByRole("status")).toHaveTextContent("This server does not support the OAuth security requirements needed to connect.");
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("");
  expect(fetchImpl).toHaveBeenCalledOnce();
  enter("Authentication Type", "cimd");
  await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Connect" })); });
  expect(screen.getByRole("alert")).toHaveTextContent("This server does not support the OAuth security requirements needed to connect.");
  expect(screen.queryByText("Discover this server's OAuth settings before connecting.")).not.toBeInTheDocument();
  expect(fetchImpl).toHaveBeenCalledOnce();
});

test("URL changes clear secrets and auth switching does not carry custom headers", () => {
  render(<CustomMcpDialog {...defaults} fetchImpl={vi.fn()} />);
  enter("MCP server URL", endpoint);
  enter("Authentication Type", "headers");
  expect(screen.getByDisplayValue("X-API-Key")).toBeInTheDocument();
  enter("Authentication Type", "bearer");
  expect(screen.queryByDisplayValue("X-API-Key")).not.toBeInTheDocument();
  enter("Bearer token", "synthetic-token");
  enter("Authentication Type", "basic");
  expect(screen.queryByDisplayValue("X-API-Key")).not.toBeInTheDocument();
  enter("Password", "synthetic-password");
  enter("MCP server URL", "https://other.example.test/mcp");
  expect(screen.queryByDisplayValue("synthetic-password")).not.toBeInTheDocument();
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("");
});

test("manual auth survives discovery and Connect sends only active credentials", async () => {
  vi.useFakeTimers();
  const onConnected = vi.fn();
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body));
    if ("revision" in body) return Response.json({ discovery: { ...body, outcome: "anonymous", suggested_method: "none", server_name: "Tools" } });
    return Response.json({ connection: { id: "id", server_name: "Tools", generation: 1, tool_count: 0 } }, { status: 201 });
  });
  render(<CustomMcpDialog {...defaults} onConnected={onConnected} fetchImpl={fetchImpl} />);
  enter("MCP server URL", endpoint);
  enter("Authentication Type", "bearer");
  enter("Bearer token", "synthetic-token");
  await act(async () => { await vi.advanceTimersByTimeAsync(400); });
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("bearer");
  await act(async () => { fireEvent.click(screen.getByRole("button", { name: "Connect" })); });
  expect(JSON.parse(String(fetchImpl.mock.calls.at(-1)?.[1]?.body))).toEqual({ endpoint, auth_method: "bearer", credentials: { token: "synthetic-token" } });
  expect(onConnected).toHaveBeenCalledOnce();
});

test("failed connection keeps the draft and never reports success", async () => {
  const onConnected = vi.fn();
  render(<CustomMcpDialog {...defaults} onConnected={onConnected} fetchImpl={vi.fn(async () => new Response("", { status: 503 }))} />);
  enter("MCP server URL", endpoint);
  enter("Authentication Type", "none");
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Could not connect"));
  expect(screen.getByLabelText("MCP server URL")).toHaveValue(endpoint);
  expect(onConnected).not.toHaveBeenCalled();
});

test("busy connections offer retry guidance without blaming credentials", async () => {
  const onConnected = vi.fn();
  const fetchImpl = vi.fn(async () => Response.json({ error: { code: "mcp_connection_busy" } }, { status: 429 }));
  render(<CustomMcpDialog {...defaults} onConnected={onConnected} fetchImpl={fetchImpl} />);
  enter("MCP server URL", endpoint);
  enter("Authentication Type", "bearer");
  enter("Bearer token", "synthetic-token");
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Connection is busy. Wait a moment, then retry."));
  expect(screen.getByRole("alert")).not.toHaveTextContent("credentials");
  expect(screen.getByLabelText("MCP server URL")).toHaveValue(endpoint);
  expect(screen.getByLabelText("Bearer token")).toHaveValue("synthetic-token");
  expect(screen.getByRole("button", { name: "Connect" })).toBeEnabled();
  expect(onConnected).not.toHaveBeenCalled();
});
