import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { ScopedServicesApp } from "./ScopedServicesApp";
import { modelCatalogFixture } from "./admin/modelCatalogFixtures";

afterEach(cleanup);
const scope = { kind: "tenant" as const, tenantKey: "Acme123456789012", tenantName: "Acme" };
const credential = { provider: "telnyx", name: "telnyx", source: "platform", status: "connected",
  credential_id: "saved-credential", platform_available: true, saved_fields: ["api_key", "public_key"], last_validated_at: null };
const application = { id: "11111111-1111-4111-8111-111111111111", name: "support", provider_connection_id: null,
  effective_application_id: "shared-app", source: "platform", outbound_number: null, published_routes: [] };
const connection = () => ({ platform_application_id: "shared-app", credential, applications: [application],
  webhook_urls: { platform: "https://calls.test/platform", tenant: "https://calls.test/Acme123456789012" } });

test("live modal reads saved configuration, saves one patch, and reloads it on reopen", async () => {
  let saved = connection();
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/telnyx-connection")) {
      if (init?.method === "PATCH") {
        const change = JSON.parse(String(init.body));
        saved = { ...saved, applications: [{ ...application, ...change, provider_connection_id: change.application_id,
          effective_application_id: change.application_id, source: "tenant" }] };
      }
      return Response.json(saved);
    }
    return Response.json({ tenant: { key: scope.tenantKey, name: "Acme" }, bindings: [credential],
      model_catalog: modelCatalogFixture, provider_capabilities: { telnyx: ["credential", "telephony"] } });
  });
  render(<ScopedServicesApp scope={scope} csrfToken="csrf-fixture" fetchImpl={fetchImpl} onNavigate={vi.fn()}
    renderInventory={({ onManage }) => <button onClick={() => onManage("telnyx")}>Manage Telnyx</button>} />);
  fireEvent.click(screen.getByRole("button", { name: "Manage Telnyx" }));
  fireEvent.click(await screen.findByRole("button", { name: "Override voice application" }));
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "acme-app" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  const writes = fetchImpl.mock.calls.filter(([, init]) => init?.method === "PATCH");
  expect(writes).toHaveLength(1);
  expect(JSON.parse(String(writes[0][1]?.body))).toEqual({ service_id: application.id, application_id: "acme-app" });
  expect(writes[0][1]?.headers).toMatchObject({ "x-csrf-token": "csrf-fixture" });
  fireEvent.click(screen.getByRole("button", { name: "Manage Telnyx" }));
  expect(await screen.findByDisplayValue("acme-app")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(fetchImpl.mock.calls.filter(([, init]) => init?.method === "PATCH")).toHaveLength(1);
});

test("multiple named applications require selection and a failed save keeps the draft", async () => {
  const second = { ...application, id: "22222222-2222-4222-8222-222222222222", name: "sales" };
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/telnyx-connection")) return init?.method === "PATCH"
      ? Response.json({ error: { code: "phone_number_in_use" } }, { status: 409 })
      : Response.json({ ...connection(), applications: [application, second] });
    return Response.json({ tenant: { key: scope.tenantKey, name: "Acme" }, bindings: [credential],
      model_catalog: modelCatalogFixture, provider_capabilities: { telnyx: ["credential", "telephony"] } });
  });
  render(<ScopedServicesApp scope={scope} csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={vi.fn()}
    renderInventory={({ onManage }) => <button onClick={() => onManage("telnyx")}>Manage Telnyx</button>} />);
  fireEvent.click(screen.getByRole("button", { name: "Manage Telnyx" }));
  fireEvent.click(await screen.findByRole("button", { name: "sales" }));
  fireEvent.click(screen.getByRole("button", { name: "Override voice application" }));
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "sales-app" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(await within(screen.getByRole("dialog")).findByRole("alert")).toHaveTextContent(/number/i);
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("sales-app");
  const write = fetchImpl.mock.calls.find(([, init]) => init?.method === "PATCH");
  expect(JSON.parse(String(write?.[1]?.body)).service_id).toBe(second.id);
});


test("Telnyx opens one persistent dialog and loads its settings directly", async () => {
  let resolve!: (response: Response) => void;
  const fetchImpl = vi.fn<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>>(() => new Promise(done => { resolve = done; }));
  render(<ScopedServicesApp scope={scope} csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={vi.fn()}
    renderInventory={({ onManage }) => <button onClick={() => onManage("telnyx")}>Edit Telnyx</button>} />);
  fireEvent.click(screen.getByRole("button", { name: "Edit Telnyx" }));
  const dialog = screen.getByRole("dialog", { name: "Telnyx" });
  const header = within(dialog).getByRole("heading", { name: "Telnyx" });
  expect(within(dialog).getByText("Acme")).toBeVisible();
  expect(within(dialog).getByRole("status")).toHaveTextContent("Loading Telnyx settings");
  expect(fetchImpl.mock.calls.map(([url]) => url)).toEqual([`/api/tenants/${scope.tenantKey}/telnyx-connection`]);
  await act(async () => resolve(Response.json(connection())));
  expect(await screen.findByDisplayValue("shared-app")).toBeVisible();
  expect(screen.getByRole("dialog")).toBe(dialog);
  expect(within(dialog).getByRole("heading", { name: "Telnyx" })).toBe(header);
  expect(within(dialog).queryByRole("status")).not.toBeInTheDocument();
});

test("Telnyx loading can be cancelled without a late response reopening the dialog", async () => {
  let resolve!: (response: Response) => void;
  const fetchImpl = vi.fn<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>>(() => new Promise(done => { resolve = done; }));
  render(<ScopedServicesApp scope={scope} csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={vi.fn()}
    renderInventory={({ onManage }) => <button onClick={() => onManage("telnyx")}>Edit Telnyx</button>} />);
  const edit = screen.getByRole("button", { name: "Edit Telnyx" });
  edit.focus();
  fireEvent.click(edit);
  expect(fetchImpl.mock.calls[0][0]).toBe(`/api/tenants/${scope.tenantKey}/telnyx-connection`);
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(fetchImpl.mock.calls[0][1]?.signal?.aborted).toBe(true);
  await act(async () => resolve(Response.json(connection())));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  await waitFor(() => expect(edit).toHaveFocus());
});
