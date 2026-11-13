import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { App } from "./test/ResourceApp";
import { modelCatalogFixture } from "./admin/modelCatalogFixtures";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/admin");
});

test.each(["", "/telephony"])("a tenant service writer edits the application only through the Telnyx modal on services%s", async category => {
  const tenant = { key: "AAAAAAAAAAAAAAAA", name: "Shared voice tenant" };
  const binding = { provider: "telnyx", name: "telnyx", source: "platform", status: "connected",
    credential_id: "saved-platform-credential", platform_available: true, saved_fields: ["api_key", "public_key"], last_validated_at: null,
    can_edit: false };
  window.history.replaceState({}, "", `/t/${tenant.key}/services${category}`);
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    const path = String(url);
    if (init?.method === "PATCH") return Response.json({});
    if (path === "/admin/api/session") return Response.json({
      user: { id: "service-writer", email: "writer@example.test", roleId: "custom", enabled: true, memberships: [] },
      role: { id: "custom", name: "Service writer", kind: null, grants: ["tenant_services.read", "tenant_services.write"]
        .map(permission => ({ permission, scope: "all_tenants" })) },
    });
    if (path.endsWith("/categories")) return Response.json({ categories: [] });
    if (path.endsWith("/service-bindings")) return Response.json({ tenant, bindings: [binding],
      model_catalog: modelCatalogFixture, provider_capabilities: { telnyx: ["credential", "telephony"] } });
    if (path.endsWith("/telnyx-connection")) return Response.json({ platform_application_id: "shared-app",
      credential: binding, applications: [{ id: "5eef6e68-11aa-434a-9a99-abc123def456", name: "support",
        provider_connection_id: null, outbound_number: null, published_routes: [] }],
      webhook_urls: { platform: "https://calls.test/platform", tenant: `https://calls.test/${tenant.key}` } });
    return Response.json({ tenant, installation_version: "0.1.0", directory_status: "local", connections: [binding],
      mcp_connections: [], page: null, fallback_items: [], local_items: [{ id: "telnyx", kind: "provider", name: "Telnyx",
        connection: { provider_id: "telnyx" }, can_connect: false, connections: [binding] }] });
  });
  render(<App csrfToken="synthetic-csrf" fetchImpl={fetchImpl} />);
  await screen.findByRole("button", { name: "Connect other MCP" });
  const edit = await screen.findByRole("button", { name: "Edit Telnyx" });
  expect(edit).toBeEnabled();
  expect(screen.queryByRole("heading", { name: "Phone routing" })).not.toBeInTheDocument();
  expect(fetchImpl.mock.calls.some(([url]) => String(url).includes("/telephony-applications"))).toBe(false);
  fireEvent.click(edit);
  fireEvent.click(await screen.findByRole("button", { name: "Override voice application" }));
  expect(screen.queryByRole("button", { name: "Override credentials" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Edit credentials" })).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "tenant-app" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  await waitFor(() => expect(fetchImpl).toHaveBeenCalledWith(`/api/tenants/${tenant.key}/telnyx-connection`,
    expect.objectContaining({ method: "PATCH", body: JSON.stringify({
      application_id: "tenant-app", service_id: "5eef6e68-11aa-434a-9a99-abc123def456",
    }) }),
  ));
});
