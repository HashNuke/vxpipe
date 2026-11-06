import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, describe, expect, it, vi } from "vitest";
import { IntegrationsDirectory } from "./IntegrationsDirectory";

afterEach(cleanup);

const row = { id: "provider-google", kind: "provider", name: "Google AI Studio", connection: { provider_id: "google" }, can_connect: true, connections: [] };
const local = { tenant: null, installation_version: "0.1.0", directory_status: "local", connections: [], page: null, local_items: [row], fallback_items: [] };
const page = { ...local, directory_status: "available", local_items: [], page: { items: [row], pagination: { total_items: 2, start_index: 1, end_index: 1, next_cursor: "opaque+/=", previous_cursor: null } } };
const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });

describe("production integrations directory", () => {
  it("replaces failed directory logos with a neutral icon and retries a new logo URL", async () => {
    let logo = "https://logos.example.test/missing.png";
    const fetcher = vi.fn(async (url: RequestInfo | URL) => response(String(url).endsWith("/categories") ? { categories: [] } : {
      ...page, tenant: { key: "tenant-a", name: "Tenant A" }, mcp_connections: [],
      page: { ...page.page, items: [{ id: "tools", kind: "mcp", name: "Tools server", connection: { endpoint: "https://mcp.example.test/mcp" }, connections: [], mcp_connections: [], can_connect: false, logo_url: logo }] },
    }));
    const view = (revision: number) => <MemoryRouter initialEntries={["/t/tenant-a/services/calendar"]}><IntegrationsDirectory tenantKey="tenant-a" fetchImpl={fetcher} onManage={vi.fn()} revision={revision} /></MemoryRouter>;
    const { rerender } = render(view(1));
    const article = await screen.findByRole("article", { name: "Tools server" });
    const image = article.querySelector("img")!;
    expect(image).toHaveAttribute("referrerpolicy", "no-referrer");
    fireEvent.error(image);
    expect(article.querySelector("img")).toBeNull();
    expect(article.querySelector("svg")).toHaveAttribute("aria-hidden", "true");
    logo = "https://logos.example.test/replacement.png";
    rerender(view(2));
    await waitFor(() => expect(article.querySelector("img")).toHaveAttribute("src", logo));
  });

  it.each(["invalid_cursor", "cursor_mismatch"])("restarts %s pages while preserving the search", async code => {
    const fetcher = vi.fn(async (url: RequestInfo | URL) => String(url).includes("cursor=")
      ? response({ error: { code, message: "private upstream diagnostic" } }, 400) : response(page));
    render(<MemoryRouter initialEntries={["/platform/services?q=calendar&cursor=broken"]}><IntegrationsDirectory tenantKey={null} fetchImpl={fetcher} onManage={vi.fn()} /></MemoryRouter>);
    expect(await screen.findByText("This page link is no longer valid for these results.")).toBeInTheDocument();
    expect(screen.queryByText("private upstream diagnostic")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Start from first page" }));
    await screen.findByRole("heading", { name: "Google AI Studio" });
    expect(fetcher.mock.calls.at(-1)?.[0]).toBe("/api/platform/integrations?q=calendar");
  });
  it("loads Connected locally and sends global search without a category", async () => {
    const fetcher = vi.fn(async (url: RequestInfo | URL) => response(String(url).includes("q=") ? page : local));
    const manage = vi.fn();
    render(<MemoryRouter initialEntries={["/platform/services"]}><IntegrationsDirectory tenantKey={null} fetchImpl={fetcher} onManage={manage} /></MemoryRouter>);
    expect(await screen.findByRole("heading", { name: "Google AI Studio" })).toBeInTheDocument();
    expect(fetcher.mock.calls[0][0]).toBe("/api/platform/integrations?category=connected");
    fireEvent.click(screen.getByRole("button", { name: "Connect Google AI Studio" }));
    expect(manage).toHaveBeenCalledWith("google", undefined);
    fireEvent.change(screen.getByRole("searchbox"), { target: { value: "google" } });
    await waitFor(() => expect(fetcher.mock.calls.some(([url]) => String(url) === "/api/platform/integrations?q=google")).toBe(true));
    expect(screen.queryByRole("button", { name: "Connect other MCP" })).not.toBeInTheDocument();
  });

  it("keeps the current page and retries the failed cursor", async () => {
    let failed = true;
    const fetcher = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).includes("cursor=") && failed) return response({ error: { code: "unavailable" } }, 503);
      return response(page);
    });
    render(<MemoryRouter initialEntries={["/platform/services/ai"]}><IntegrationsDirectory tenantKey={null} fetchImpl={fetcher} onManage={vi.fn()} /></MemoryRouter>);
    await screen.findByRole("heading", { name: "Google AI Studio" });
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(await screen.findByRole("button", { name: "Retry page" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Google AI Studio" })).toBeInTheDocument();
    failed = false;
    fireEvent.click(screen.getByRole("button", { name: "Retry page" }));
    await waitFor(() => expect(screen.queryByRole("button", { name: "Retry page" })).not.toBeInTheDocument());
    expect(fetcher.mock.calls.at(-1)?.[0]).toContain("cursor=opaque%2B%2F%3D");
  });
});


it.each([
  { tenantKey: null, source: "platform", canEdit: false },
  { tenantKey: "tenant-a", source: "platform", canEdit: true },
])("does not offer credential removal for a read-only or inherited connection: %j", async ({ tenantKey, source, canEdit }) => {
  const binding = { provider: "google", name: "secondary", source, status: "connected", credential_id: "private-id", can_edit: canEdit };
  const inventory = { ...local, tenant: tenantKey ? { key: tenantKey, name: "Tenant A" } : null,
    connections: [binding], local_items: [{ ...row, can_connect: false, connections: [binding] }] };
  const fetcher = vi.fn(async (url: RequestInfo | URL) => response(String(url).endsWith("/categories") ? { categories: [] } : inventory));
  const remove = vi.fn();
  render(<MemoryRouter initialEntries={[tenantKey ? `/t/${tenantKey}/services` : "/platform/services"]}>
    <IntegrationsDirectory tenantKey={tenantKey} fetchImpl={fetcher} onManage={vi.fn()} onRemove={remove} />
  </MemoryRouter>);
  await screen.findByRole("article", { name: "Google AI Studio" });
  expect(screen.queryByRole("button", { name: /Remove/ })).not.toBeInTheDocument();
  expect(remove).not.toHaveBeenCalled();
  if (!canEdit) expect(screen.getByRole("button", { name: "Edit Google AI Studio" })).toBeDisabled();
});

it("connects, manages and disconnects a tenant MCP through the live inventory controls", async () => {
  let connected = false;
  const saved = { id: "mcp-id", tenant_key: "tenant-a", endpoint: "https://mcp.example.test/mcp", server_name: "Tools server", auth_method: "none", generation: 1, status: "connected", tool_count: 0, can_edit: true };
  const fetcher = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    const path = String(url);
    if (path.endsWith("/categories")) return response({ categories: [] });
    if (init?.method === "POST" && path.endsWith("/mcp-connections")) { connected = true; return response({ connection: saved }, 201); }
    if (init?.method === "DELETE") { connected = false; return response({ connection: { ...saved, generation: 2, status: "revoked" } }); }
    if (path.endsWith("/mcp-connections/mcp-id")) return response({ connection: { ...saved, tools: [] } });
    return response({ ...local, tenant: { key: "tenant-a", name: "Tenant A" }, mcp_connections: connected ? [saved] : [], local_items: connected ? [{ id: "mcp-mcp-id", kind: "mcp", name: "Tools server", connection: { endpoint: saved.endpoint }, connections: [], mcp_connections: [saved], can_connect: false }] : [] });
  });
  render(<MemoryRouter initialEntries={["/t/tenant-a/services"]}><IntegrationsDirectory tenantKey="tenant-a" csrfToken="csrf" canManageMcps fetchImpl={fetcher} onManage={vi.fn()} /></MemoryRouter>);
  fireEvent.click(await screen.findByRole("button", { name: "Connect other MCP" }));
  fireEvent.change(screen.getByLabelText("MCP server URL"), { target: { value: saved.endpoint } });
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "none" } });
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(await screen.findByRole("article", { name: "Tools server" })).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Manage Tools server" }));
  expect(await screen.findByRole("dialog", { name: "Tools server" })).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Disconnect" }));
  await waitFor(() => expect(screen.queryByRole("article", { name: "Tools server" })).not.toBeInTheDocument());
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

it("read-only tenant users can inspect saved MCPs but cannot connect or disconnect", async () => {
  const saved = { id: "mcp-id", tenant_key: "tenant-a", endpoint: "https://mcp.example.test/mcp", server_name: "Tools server", auth_method: "none", generation: 1, status: "connected", tool_count: 0, can_edit: false };
  const fetcher = vi.fn(async (url: RequestInfo | URL) => response(String(url).endsWith("/categories") ? { categories: [] } : String(url).endsWith("/mcp-id") ? { connection: { ...saved, tools: [] } } : { ...local, tenant: { key: "tenant-a", name: "Tenant A" }, mcp_connections: [saved], local_items: [{ id: "mcp-mcp-id", kind: "mcp", name: "Tools server", connection: { endpoint: saved.endpoint }, connections: [], mcp_connections: [saved], can_connect: false }] }));
  render(<MemoryRouter initialEntries={["/t/tenant-a/services"]}><IntegrationsDirectory tenantKey="tenant-a" csrfToken="csrf" canEdit={false} fetchImpl={fetcher} onManage={vi.fn()} /></MemoryRouter>);
  fireEvent.click(await screen.findByRole("button", { name: "Manage Tools server" }));
  expect(screen.queryByRole("button", { name: "Connect other MCP" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Disconnect" })).not.toBeInTheDocument();
});
