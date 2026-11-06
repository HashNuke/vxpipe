import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, expect, test, vi } from "vitest";
import { IntegrationsApp } from "./IntegrationsApp";
import { modelCatalogFixture } from "./admin/modelCatalogFixtures";
import { App } from "./test/ResourceApp";

afterEach(cleanup);

test("the production Services route is replaced with Integrations", async () => {
  window.history.replaceState({}, "", "/platform/services");
  const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
    if (String(url) === "/admin/api/session") return Response.json({
      user: { id: "owner", email: "owner@example.test", roleId: "admin", enabled: true, memberships: [] },
      role: { id: "admin", name: "Admin", description: "", kind: "admin", grants: [] },
    });
    if (String(url).includes("/integrations?")) return Response.json({ tenant: null, installation_version: "0.1.0",
      directory_status: "local", connections: [], page: null, fallback_items: [], local_items: [] });
    return Response.json({ tenant: null, bindings: [], model_catalog: modelCatalogFixture,
      provider_capabilities: { google: ["credential", "llm"] } });
  });
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  expect(await screen.findByRole("heading", { name: "Platform Integrations" })).toBeVisible();
  expect(await screen.findByText("No connected integrations")).toBeVisible();
  expect(fetchImpl.mock.calls.some(([url]) => String(url) === "/api/platform/services")).toBe(false);
});

test("production integration browsing opens the existing native credential form", async () => {
  const fetchImpl = vi.fn(async (url: RequestInfo | URL) => Response.json(String(url).includes("/integrations?") ? {
    tenant: null, installation_version: "0.1.0", directory_status: "local", connections: [], page: null,
    fallback_items: [], local_items: [{ id: "provider-google", kind: "provider", name: "Google AI Studio",
      connection: { provider_id: "google" }, capabilities: ["llm"], can_connect: true, connections: [] }],
  } : { tenant: null, bindings: [], model_catalog: modelCatalogFixture, provider_capabilities: { google: ["credential", "llm"] } }));
  render(<MemoryRouter initialEntries={["/platform/services"]}><IntegrationsApp scope={{ kind: "platform" }} csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={vi.fn()} /></MemoryRouter>);
  await screen.findByRole("button", { name: "Connect Google AI Studio" });
  expect(screen.getByText("LLM")).toBeVisible();
  expect(screen.queryByText("Speech-to-text")).not.toBeInTheDocument();
  fireEvent.click(await screen.findByRole("button", { name: "Connect Google AI Studio" }));
  expect(await screen.findByRole("dialog")).toBeVisible();
  expect(screen.getByLabelText(/API key/i)).toBeVisible();
  expect(fetchImpl.mock.calls.filter(([url]) => String(url) === "/api/platform/services")).toHaveLength(1);
});


test("removes the exact named native connection from the production inventory", async () => {
  let removed = false;
  const binding = { provider: "google", name: "secondary", source: "platform", status: "connected",
    credential_id: "secondary-id", platform_available: false, saved_fields: ["api_key"], last_validated_at: null };
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (init?.method === "DELETE") { removed = true; return new Response(null, { status: 204 }); }
    const bindings = removed ? [] : [binding];
    return Response.json(String(url).includes("/integrations?") ? {
      tenant: null, installation_version: "0.1.0", directory_status: "local", connections: bindings.map(value => ({ ...value, can_edit: true })), page: null,
      fallback_items: [], local_items: removed ? [] : [{ id: "provider-google", kind: "provider", name: "Google AI Studio",
        connection: { provider_id: "google" }, can_connect: false, connections: [{ ...binding, can_edit: true }] }],
    } : { tenant: null, bindings, model_catalog: modelCatalogFixture, provider_capabilities: { google: ["credential", "llm"] } });
  });
  render(<MemoryRouter initialEntries={["/platform/services"]}><IntegrationsApp scope={{ kind: "platform" }} csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={vi.fn()} /></MemoryRouter>);
  fireEvent.click(await screen.findByRole("button", { name: "Remove Google AI Studio (secondary) credentials" }));
  expect(await screen.findByText("No connected integrations")).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith("/api/platform/credentials/secondary-id", expect.objectContaining({
    method: "DELETE", headers: expect.objectContaining({ "x-csrf-token": "csrf" }),
  }));
});

test("inherited native integrations open tenant override controls without navigating away", async () => {
  const binding = { provider: "google", name: "google", source: "platform", status: "connected",
    credential_id: "platform-google", platform_available: true, saved_fields: ["api_key"], last_validated_at: null };
  const onNavigate = vi.fn();
  const fetchImpl = vi.fn(async (url: RequestInfo | URL) => Response.json(String(url).includes("/integrations?") ? {
    tenant: { key: "demo", name: "Demo" }, installation_version: "0.1.0", directory_status: "local", page: null,
    connections: [{ ...binding, can_edit: false }], fallback_items: [], local_items: [{ id: "provider-google", kind: "provider", name: "Google AI Studio",
      connection: { provider_id: "google" }, can_connect: false, connections: [{ ...binding, can_edit: false }] }],
  } : { tenant: { key: "demo", name: "Demo" }, bindings: [binding], model_catalog: modelCatalogFixture,
    provider_capabilities: { google: ["credential", "llm"] } }));
  render(<MemoryRouter initialEntries={["/t/demo/services"]}><IntegrationsApp scope={{ kind: "tenant", tenantKey: "demo", tenantName: "Demo" }} csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={onNavigate} /></MemoryRouter>);
  fireEvent.click(await screen.findByRole("button", { name: "Edit Google AI Studio" }));
  fireEvent.click(await screen.findByRole("button", { name: "Override for this tenant" }));
  expect(screen.getByLabelText(/API key/i)).toBeVisible();
  expect(onNavigate).not.toHaveBeenCalled();
});

test("restores a named tenant override without deleting platform credentials", async () => {
  let restored = false;
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (init?.method === "DELETE") { restored = true; return new Response(null, { status: 204 }); }
    const binding = { provider: "google", name: "secondary", source: restored ? "platform" : "tenant", status: "connected",
      credential_id: restored ? "platform-google" : "tenant-google", platform_available: true, saved_fields: ["api_key"], last_validated_at: null };
    return Response.json(String(url).includes("/integrations?") ? {
      tenant: { key: "demo", name: "Demo" }, installation_version: "0.1.0", directory_status: "local", page: null,
      connections: [{ ...binding, can_edit: !restored }], fallback_items: [], local_items: [{ id: "provider-google", kind: "provider", name: "Google AI Studio",
        connection: { provider_id: "google" }, can_connect: false, connections: [{ ...binding, can_edit: !restored }] }],
    } : { tenant: { key: "demo", name: "Demo" }, bindings: [binding], model_catalog: modelCatalogFixture,
      provider_capabilities: { google: ["credential", "llm"] } });
  });
  render(<MemoryRouter initialEntries={["/t/demo/services"]}><IntegrationsApp scope={{ kind: "tenant", tenantKey: "demo", tenantName: "Demo" }} csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={vi.fn()} /></MemoryRouter>);
  fireEvent.click(await screen.findByRole("button", { name: "Edit Google AI Studio" }));
  fireEvent.click(await screen.findByRole("button", { name: "Use platform service" }));
  await screen.findByText("Credentials removed.");
  expect(fetchImpl).toHaveBeenCalledWith("/api/tenants/demo/credentials/tenant-google", expect.objectContaining({ method: "DELETE" }));
  expect(fetchImpl.mock.calls.filter(([, init]) => init?.method === "DELETE")).toHaveLength(1);
  fireEvent.click(await screen.findByRole("button", { name: "Edit Google AI Studio" }));
  expect(await screen.findByRole("button", { name: "Override for this tenant" })).toBeVisible();
});


test("production navigation retains the current page when the next cursor fails", async () => {
  let failed = true;
  const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
    if (String(url).includes("cursor=") && failed) return new Response("", { status: 503 });
    return Response.json({ tenant: null, installation_version: "0.1.0", directory_status: "available", connections: [], local_items: [], fallback_items: [],
      page: { items: [{ id: "google", kind: "provider", name: "Google AI Studio", connection: { provider_id: "google" }, can_connect: true, connections: [] }],
        pagination: { total_items: 2, start_index: 1, end_index: 1, next_cursor: "next-cursor", previous_cursor: null } } });
  });
  render(<MemoryRouter initialEntries={["/platform/services/ai"]}><IntegrationsApp scope={{ kind: "platform" }} csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={vi.fn()} /></MemoryRouter>);
  await screen.findByRole("heading", { name: "Google AI Studio" });
  fireEvent.click(screen.getByRole("button", { name: "Next" }));
  expect(await screen.findByRole("button", { name: "Retry page" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "Google AI Studio" })).toBeVisible();
  failed = false;
  fireEvent.click(screen.getByRole("button", { name: "Retry page" }));
  await waitFor(() => expect(screen.queryByRole("button", { name: "Retry page" })).not.toBeInTheDocument());
  expect(fetchImpl.mock.calls.at(-1)?.[0]).toContain("cursor=next-cursor");
});

test.each(["tenant_services.write", "tenant_api_keys.write", "platform_services.write"])("production route separates MCP and native permission: %s", async permission => {
  window.history.replaceState({}, "", "/t/acme_demo_000001/services");
  const serviceWriter = permission === "tenant_services.write";
  const saved = { id: "mcp-id", tenant_key: "acme_demo_000001", endpoint: "https://mcp.example.test/mcp", server_name: "Tools server", auth_method: "none", generation: 1, status: "connected", tool_count: 0, can_edit: serviceWriter };
  const binding = { provider: "google", name: "google", source: "platform", status: "connected", credential_id: "platform-google", can_edit: permission === "platform_services.write" };
  const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
    const path = String(url);
    if (path === "/admin/api/session") return Response.json({ user: { id: "member", email: "member@example.test", roleId: "member", enabled: true, memberships: [] },
      role: { id: "member", name: "Member", kind: null, grants: ["tenant_services.read", permission].map(permission => ({ permission, scope: permission.startsWith("platform_") ? "installation" : "all_tenants" })) } });
    if (path.endsWith("/categories")) return Response.json({ categories: [] });
    if (path.endsWith("/mcp-id")) return Response.json({ connection: { ...saved, tools: [] } });
    return Response.json({ tenant: { key: "acme_demo_000001", name: "Demo" }, installation_version: "0.1.0", directory_status: "local", connections: [binding], mcp_connections: [saved], page: null, fallback_items: [], local_items: [
      { id: "google", kind: "provider", name: "Google AI Studio", connection: { provider_id: "google" }, can_connect: false, connections: [binding] },
      { id: "mcp", kind: "mcp", name: "Tools server", connection: { endpoint: saved.endpoint }, can_connect: false, connections: [], mcp_connections: [saved] },
    ] });
  });
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  await screen.findByRole("article", { name: "Tools server" });
  await waitFor(() => expect(screen.getByRole("button", { name: "Edit Google AI Studio" }).hasAttribute("disabled")).toBe(permission !== "tenant_api_keys.write"));
  if (serviceWriter) expect(await screen.findByRole("button", { name: "Connect other MCP" })).toBeEnabled();
  else expect(screen.queryByRole("button", { name: "Connect other MCP" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Manage Tools server" }));
  if (serviceWriter) expect(screen.getByRole("button", { name: "Disconnect" })).toBeEnabled();
  else expect(screen.queryByRole("button", { name: "Disconnect" })).not.toBeInTheDocument();
});


test.each(["local", "unavailable"])("read-only native rows show installed capabilities before settings are opened: %s", async status => {
  const row = { id: "provider-google", kind: "provider", name: "Google AI Studio", capabilities: ["llm"],
    connection: { provider_id: "google" }, can_connect: false, connections: [] };
  const fetchImpl = vi.fn(async () => Response.json({ tenant: null, installation_version: "0.1.0", directory_status: status,
    connections: [], page: null, local_items: status === "local" ? [row] : [], fallback_items: status === "unavailable" ? [row] : [] }));
  render(<MemoryRouter initialEntries={["/platform/services"]}><IntegrationsApp scope={{ kind: "platform" }} csrfToken="csrf" canEdit={false} fetchImpl={fetchImpl} onNavigate={vi.fn()} /></MemoryRouter>);
  expect(await screen.findByText("LLM")).toBeVisible();
  expect(screen.getByRole("img", { name: "Google AI Studio service logo" })).toBeVisible();
  expect(screen.queryByText("Speech-to-text")).not.toBeInTheDocument();
  expect(fetchImpl.mock.calls).toHaveLength(1);
});
