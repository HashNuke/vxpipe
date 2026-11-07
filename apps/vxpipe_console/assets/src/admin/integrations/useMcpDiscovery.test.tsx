import { act, cleanup, renderHook } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { useMcpDiscovery } from "./useMcpDiscovery";
import type { McpListingReference } from "./listedMcp";
afterEach(() => { cleanup(); vi.useRealTimers(); });
const response = (discovery: unknown) => new Response(JSON.stringify({ discovery }), { status: 200 });
const base = { tenantKey: "tenant-a", csrfToken: "csrf", endpoint: "https://mcp.example.test/mcp", revision: "1", active: true, onSessionExpired: vi.fn() };
const advance = async () => act(async () => { await vi.advanceTimersByTimeAsync(400); });

test("saved discovery binds its advisory registration choice to connection and generation", async () => {
  vi.useFakeTimers();
  const connection = { connection_id: "saved", generation: 7 };
  const fetchImpl = vi.fn(async () => response({ endpoint: base.endpoint, revision: "1", outcome: "oauth", suggested_method: "dcr",
    ...connection, generation: 6, oauth_registration: { method: "dcr", reusable: true } }));
  const { result } = renderHook(() => useMcpDiscovery({ ...base, connection, fetchImpl }));
  await advance();
  expect(fetchImpl).toHaveBeenCalledWith("/api/tenants/tenant-a/mcp-discovery", expect.objectContaining({ body: JSON.stringify({ ...connection, revision: "1" }) }));
  expect(result.current.status).toBe("failed");
  expect(result.current.data).toBeNull();
});

test("listed discovery sends only its reference and rejects a different accepted entry", async () => {
  vi.useFakeTimers();
  const listing: McpListingReference = { directory_id: "directory", integration_id: "calendar", entry_revision: 1, page: { scope: "tenant" } };
  const fetchImpl = vi.fn(async () => response({ endpoint: base.endpoint, revision: "1", outcome: "oauth", suggested_method: "cimd",
    listing: { directory_id: "other", integration_id: "calendar", revision: 1, name: "Calendar", endpoint: base.endpoint, authentication: { type: "oauth2", registration: "discover" } } }));
  const { result } = renderHook(() => useMcpDiscovery({ ...base, listing, fetchImpl }));
  await advance();
  expect(fetchImpl).toHaveBeenCalledWith("/api/tenants/tenant-a/mcp-discovery", expect.objectContaining({ body: JSON.stringify({ listing, revision: "1" }) }));
  expect(result.current.status).toBe("failed");
  expect(result.current.data).toBeNull();
});

test("debounces a credentialless same-origin request with CSRF and accepts matching results", async () => {
  vi.useFakeTimers();
  const fetchImpl = vi.fn(async () => response({ endpoint: base.endpoint, revision: "1", outcome: "anonymous", suggested_method: "none", server_name: "Tools" }));
  const { result } = renderHook(() => useMcpDiscovery({ ...base, fetchImpl }));
  expect(fetchImpl).not.toHaveBeenCalled();
  await advance();
  expect(fetchImpl).toHaveBeenCalledWith("/api/tenants/tenant-a/mcp-discovery", expect.objectContaining({
    method: "POST", credentials: "same-origin", headers: expect.objectContaining({ "x-csrf-token": "csrf" }),
    body: JSON.stringify({ endpoint: base.endpoint, revision: "1" }),
  }));
  expect(result.current.status).toBe("ready");
  expect(result.current.data?.suggestedMethod).toBe("none");
});

test("URL/revision changes abort the previous request and reject late results", async () => {
  vi.useFakeTimers();
  let finish!: (value: Response) => void;
  const fetchImpl = vi.fn<(url: RequestInfo | URL, init?: RequestInit) => Promise<Response>>(() => new Promise<Response>(resolve => { finish = resolve; }));
  const { result, rerender } = renderHook(props => useMcpDiscovery({ ...base, ...props, fetchImpl }), { initialProps: { endpoint: base.endpoint, revision: "1" } });
  await advance();
  const oldFinish = finish;
  const oldSignal = fetchImpl.mock.calls[0][1]?.signal;
  rerender({ endpoint: "https://next.example.test/mcp", revision: "2" });
  expect(oldSignal?.aborted).toBe(true);
  await act(async () => { oldFinish(response({ endpoint: base.endpoint, revision: "1", outcome: "anonymous", suggested_method: "none" })); });
  expect(result.current.data).toBeNull();
  await advance();
  await act(async () => { finish(response({ endpoint: base.endpoint, revision: "1", outcome: "anonymous", suggested_method: "none" })); });
  expect(result.current.status).toBe("failed");
  expect(result.current.data).toBeNull();
});

test("invalid URL and closed modal never probe; session expiry is handled", async () => {
  vi.useFakeTimers();
  const onSessionExpired = vi.fn();
  const fetchImpl = vi.fn(async () => new Response("", { status: 401 }));
  const { rerender, result } = renderHook(props => useMcpDiscovery({ ...base, ...props, fetchImpl, onSessionExpired }), { initialProps: { endpoint: "https://", active: true } });
  await advance();
  expect(fetchImpl).not.toHaveBeenCalled();
  rerender({ endpoint: base.endpoint, active: false });
  await advance();
  expect(fetchImpl).not.toHaveBeenCalled();
  rerender({ endpoint: base.endpoint, active: true });
  await advance();
  expect(onSessionExpired).toHaveBeenCalledOnce();
  expect(result.current.data).toBeNull();
});
