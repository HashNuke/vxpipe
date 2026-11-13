import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { TenantTelephonyApplications } from "./admin/TenantTelephonyApplications";
import { App } from "./test/ResourceApp";
import { modelCatalogFixture } from "./admin/modelCatalogFixtures";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/admin");
});

test("an inherited application can save its outbound caller number without becoming dedicated", async () => {
  const tenant = { key: "AAAAAAAAAAAAAAAA", name: "Shared voice tenant" };
  const application = {
    id: "5eef6e68-11aa-434a-9a99-abc123def456",
    name: "support",
    provider_connection_id: null,
    outbound_number: null,
    published_routes: [],
  };
  const prefix = `/api/tenants/${tenant.key}/telephony-applications`;
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) =>
    Response.json(init?.method === "PATCH"
      ? { application: { ...application, ...JSON.parse(String(init.body)) } }
      : { tenant, applications: [application], truncated: false }),
  );

  render(<TenantTelephonyApplications tenantKey={tenant.key} csrfToken="synthetic-csrf"
    credentialsLoaded binding={{ provider: "telnyx", name: "telnyx", source: "platform",
      status: "connected", credentialId: "saved-platform-credential", platformAvailable: true,
      savedFields: ["apiKey", "publicKey"], telephonyPublicKeyConfigured: true,
      lastValidatedAt: null }}
    webhookUrl="https://callbacks.example.test/webhooks/platform/telnyx"
    fetchImpl={fetchImpl} onConnectionDetails={vi.fn()} onSessionExpired={vi.fn()} />);

  fireEvent.click(await screen.findByRole("button", { name: "Edit support" }));
  fireEvent.change(screen.getByLabelText("Outbound caller number (optional)"), {
    target: { value: "+15550002000" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save application" }));

  await waitFor(() => expect(fetchImpl).toHaveBeenCalledWith(`${prefix}/${application.id}`,
    expect.objectContaining({ method: "PATCH", body: JSON.stringify({
      provider_connection_id: null, outbound_number: "+15550002000",
    }) }),
  ));
});

test("a tenant service writer can open Telnyx to change only the application", async () => {
  const tenant = { key: "AAAAAAAAAAAAAAAA", name: "Shared voice tenant" };
  const binding = { provider: "telnyx", name: "telnyx", source: "platform", status: "connected",
    credential_id: "saved-platform-credential", platform_available: true, saved_fields: ["api_key", "public_key"], last_validated_at: null,
    can_edit: false };
  window.history.replaceState({}, "", `/t/${tenant.key}/services`);
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
