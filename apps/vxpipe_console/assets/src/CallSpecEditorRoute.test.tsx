import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { App } from "./test/ResourceApp";
import { modelCatalogFixture } from "./admin/modelCatalogFixtures";
import type { CatalogCapability } from "./admin/modelCatalog";
import { newCallSpec } from "./admin/callSpecEditor/seed";
import type { FlowCanvasProps } from "./admin/callSpecEditor/flow-canvas";

vi.mock("./admin/callSpecEditor/flow-canvas", () => ({ FlowCanvas: ({ onSelectNode }: FlowCanvasProps) => <div>Flow canvas<button onClick={() => onSelectNode("assistant")}>Select assistant</button></div> }));
afterEach(() => { cleanup(); window.history.replaceState({}, "", "/admin"); });
const source = { ...newCallSpec(modelCatalogFixture, { direction: "incoming" }).source, name: "Original" };
if (source.participants.assistant?.type === "agent") source.participants.assistant.prompt = "Handle appointment requests.";
const stored = { call_spec_id: "1c94f0f7-05d5-4919-a7d5-01d7250e4caf", revision: 2, latest_revision: 2, published_revision: 1, source };
const reply = (body: unknown, status = 200) => Promise.resolve(new Response(JSON.stringify(body), { status }));
function transport() {
  return vi.fn((input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const url = new URL(String(input), "https://console.test");
    if (url.pathname === "/admin/api/session") return reply({
      user: { id: "owner", email: "owner@example.test", roleId: "admin", enabled: true, memberships: [] },
      role: { id: "admin", name: "Admin", description: "", kind: "admin", grants: [] },
    });
    if (url.pathname.endsWith("/call-spec-editor-lookups")) return reply({ credential_names: {}, telephony_services: [], mcp_integrations: [] });
    if (url.pathname.includes("/providers")) {
      const models = modelCatalogFixture[url.searchParams.get("capability") as CatalogCapability] ?? {};
      return url.pathname.endsWith("/models") ? reply({ models: models[url.pathname.split("/").at(-2)!] }) : reply({ providers: Object.keys(models).map((id) => ({ id })) });
    }
    if (init?.method === "POST" || init?.method === "PUT") return reply({ call_spec: stored }, 201);
    if (url.pathname.endsWith("/1c94f0f7-05d5-4919-a7d5-01d7250e4caf")) return reply({ call_spec: stored });
    if (url.pathname.endsWith("/call-specs")) return reply({ tenant: { key: "AAAAAAAAAAAAAAAA", name: "Demo" }, call_specs: [], pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 } });
    return reply({}, 404);
  });
}
const createIncoming = async () => {
  fireEvent.click(await screen.findByRole("radio", { name: "Incoming call" }));
  fireEvent.click(screen.getByRole("button", { name: "Create call spec" }));
};
const saveDraft = () => {
  fireEvent.keyDown(screen.getByRole("button", { name: "More actions" }), { key: "ArrowDown" });
  fireEvent.click(screen.getByRole("menuitem", { name: "Save as draft" }));
};
const rename = (value: string) => {
  fireEvent.click(screen.getByRole("button", { name: "Edit call spec name" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Call spec name" }), { target: { value } });
  fireEvent.click(screen.getByRole("button", { name: "Save name" }));
};
const writeInitialPrompt = () => {
  fireEvent.click(screen.getByRole("button", { name: "Select assistant" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Prompt" }), { target: { value: "Handle appointment requests." } });
};

test("new route creates a spec, replaces its URL without losing edits, and publishes saved identity", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/new");
  const fetch = transport(); render(<App csrfToken="csrf" fetchImpl={fetch} />);
  await createIncoming();
  await screen.findByRole("button", { name: "Edit call spec name" }); rename("New draft");
  expect(screen.queryByLabelText(/public.?id|call spec id/i)).not.toBeInTheDocument();
  saveDraft();
  expect(fetch.mock.calls.some(([, init]) => init?.method === "POST")).toBe(false);
  writeInitialPrompt();
  saveDraft();
  await screen.findByText("Saved as revision 2");
  const submitted = fetch.mock.calls.find(([, init]) => init?.method === "POST");
  expect(Object.keys(JSON.parse(String(submitted?.[1]?.body)))).toEqual(["source"]);
  await waitFor(() => expect(window.location.pathname).toBe("/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/1c94f0f7-05d5-4919-a7d5-01d7250e4caf"));
  expect(screen.getByRole("button", { name: "Edit call spec name" })).toHaveTextContent("New draft");
  fireEvent.click(screen.getByRole("button", { name: "Publish" }));
  await screen.findByText("Published revision 2");
  expect(fetch).toHaveBeenCalledWith("/api/tenants/AAAAAAAAAAAAAAAA/call-specs/1c94f0f7-05d5-4919-a7d5-01d7250e4caf/revisions/2/publish", expect.objectContaining({ body: "{}" }));
});

test("session expiry keeps the source and disables writes without navigating away", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/1c94f0f7-05d5-4919-a7d5-01d7250e4caf");
  const fetch = transport(); const expired = vi.fn(); render(<App csrfToken="csrf" fetchImpl={fetch} onSessionExpired={expired} />);
  await screen.findByRole("button", { name: "Edit call spec name" }); rename("Keep this draft");
  fetch.mockImplementation(() => reply({}, 401));
  saveDraft();
  await screen.findByText(/Your session expired/);
  expect(expired).not.toHaveBeenCalled();
  expect(screen.getByRole("button", { name: "Edit call spec name" })).toHaveTextContent("Keep this draft");
  fireEvent.keyDown(screen.getByRole("button", { name: "More actions" }), { key: "ArrowDown" });
  expect(screen.getByRole("menuitem", { name: "Save as draft" })).toHaveAttribute("aria-disabled", "true");
  fireEvent.keyDown(screen.getByRole("menu"), { key: "Escape" });
});

test("browser back and editor Back use a single discard confirmation", async () => {
  window.history.replaceState({}, "", "/t/AAAAAAAAAAAAAAAA/call-specs");
  window.history.pushState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/1c94f0f7-05d5-4919-a7d5-01d7250e4caf");
  render(<App csrfToken="csrf" fetchImpl={transport()} />);
  await screen.findByRole("button", { name: "Edit call spec name" }); rename("Unsaved");
  fireEvent.click(screen.getByRole("link", { name: "Back to call specs" }));
  fireEvent.click(screen.getByRole("button", { name: "Keep editing" }));
  expect(screen.getByRole("button", { name: "Edit call spec name" })).toHaveTextContent("Unsaved");
  fireEvent.click(screen.getByRole("link", { name: "Back to call specs" }));
  fireEvent.click(screen.getByRole("button", { name: "Leave page" }));
  await screen.findByText("No call specs yet");
  expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
});

test("explicit revisions are read-only and can open the latest editable revision", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/1c94f0f7-05d5-4919-a7d5-01d7250e4caf?revision=1");
  render(<App csrfToken="csrf" fetchImpl={transport()} />);
  await screen.findByText(/Viewing revision/);
  fireEvent.keyDown(screen.getByRole("button", { name: "More actions" }), { key: "ArrowDown" });
  expect(screen.getByRole("menuitem", { name: "Save as draft" })).toHaveAttribute("aria-disabled", "true");
  fireEvent.keyDown(screen.getByRole("menu"), { key: "Escape" });
  fireEvent.click(screen.getByRole("link", { name: "Continue editing latest revision" }));
  await waitFor(() => expect(screen.getByRole("button", { name: "More actions" })).toBeEnabled());
  expect(window.location.search).toBe("");
});

test("failed initial reads show Retry and unmount aborts requests", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/1c94f0f7-05d5-4919-a7d5-01d7250e4caf");
  const fetch = transport(); const good = fetch.getMockImplementation()!;
  fetch.mockImplementation((input, init) => String(input).endsWith("/1c94f0f7-05d5-4919-a7d5-01d7250e4caf") ? reply({}, 503) : good(input, init));
  const view = render(<App csrfToken="csrf" fetchImpl={fetch} />);
  await screen.findByText("Call spec unavailable");
  fetch.mockImplementation(good); fireEvent.click(screen.getByRole("button", { name: "Retry" }));
  await screen.findByRole("button", { name: "Edit call spec name" });
  const signal = fetch.mock.calls.at(-1)?.[1]?.signal;
  act(() => view.unmount()); expect(signal?.aborted).toBe(true);
});

test("browser history back restores the editor until discard is confirmed", async () => {
  window.history.replaceState({}, "", "/t/AAAAAAAAAAAAAAAA/call-specs");
  render(<App csrfToken="csrf" fetchImpl={transport()} />);
  fireEvent.click(await screen.findByRole("link", { name: "New call spec" }));
  await createIncoming();
  await screen.findByRole("button", { name: "Edit call spec name" }); rename("Unsaved history");
  act(() => window.history.back());
  await screen.findByRole("alertdialog");
  fireEvent.click(screen.getByRole("button", { name: "Keep editing" }));
  expect(screen.getByRole("button", { name: "Edit call spec name" })).toHaveTextContent("Unsaved history");
  await waitFor(() => { expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument(); expect(window.location.pathname).toBe("/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/new"); });
  act(() => window.history.back());
  await screen.findByRole("alertdialog");
  fireEvent.click(screen.getByRole("button", { name: "Leave page" }));
  await screen.findByText("No call specs yet");
});

test("URL replacement after creation preserves changes made during the request", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/new");
  const fetch = transport(); const good = fetch.getMockImplementation()!;
  let complete!: (response: Response) => void;
  fetch.mockImplementation((input, init) => init?.method === "POST" ? new Promise((resolve) => { complete = resolve; }) : good(input, init));
  render(<App csrfToken="csrf" fetchImpl={fetch} />);
  await createIncoming();
  await screen.findByRole("button", { name: "Edit call spec name" }); rename("Sent draft");
  writeInitialPrompt();
  fireEvent.click(screen.getByRole("button", { name: "Add agent" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Prompt" }), { target: { value: "Review appointment requests." } });
  saveDraft();
  fireEvent.change(screen.getByRole("textbox", { name: "Prompt" }), { target: { value: "Newer prompt" } });
  await act(async () => complete(await reply({ call_spec: stored }, 201)));
  expect(await screen.findByText("Saved as revision 2")).toBeVisible();
  expect(window.location.pathname).toBe("/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/1c94f0f7-05d5-4919-a7d5-01d7250e4caf");
  expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveValue("Newer prompt");
  expect(screen.getByText("Unsaved changes")).toBeVisible();
  expect(screen.getByRole("button", { name: "Publish" })).toBeDisabled();
});

test("the list opens a saved spec by its server-generated public UUID", async () => {
  window.history.replaceState({}, "", "/t/AAAAAAAAAAAAAAAA/call-specs");
  const fetch = transport(); const good = fetch.getMockImplementation()!;
  fetch.mockImplementation((input, init) => {
    const path = new URL(String(input), "https://console.test").pathname;
    if (path.endsWith("/call-specs")) return reply({
      tenant: { key: "AAAAAAAAAAAAAAAA", name: "Demo" },
      call_specs: [{ id: stored.call_spec_id, name: "Existing API-authored spec", latest_revision: 2,
        published_revision: 1, call_count: 0, updated_at: "2026-10-08T00:00:00Z" }],
      pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
    });
    if (path.endsWith("/call-specs/1c94f0f7-05d5-4919-a7d5-01d7250e4caf")) return reply({ call_spec: { ...stored, call_spec_id: stored.call_spec_id } });
    return good(input, init);
  });
  render(<App csrfToken="csrf" fetchImpl={fetch} />);
  fireEvent.click(await screen.findByRole("link", { name: "Existing API-authored spec" }));
  expect(await screen.findByRole("button", { name: "Edit call spec name" })).toHaveTextContent("Original");
  expect(screen.getByText("v2")).toBeVisible();
});


test("new specs ask for direction before showing the editor", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/new");
  const fetch = transport(); render(<App csrfToken="csrf" fetchImpl={fetch} />);
  expect(await screen.findByRole("heading", { name: "New call spec" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "More actions" })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Create call spec" })).toBeDisabled();
  fireEvent.click(screen.getByRole("radio", { name: /Incoming call/ }));
  fireEvent.click(screen.getByRole("button", { name: "Create call spec" }));
  expect(await screen.findByRole("button", { name: "More actions" })).toBeEnabled();
  expect(fetch.mock.calls.some(([, init]) => init?.method === "POST")).toBe(false);
});

test("outgoing creation requires a phone service and saves the chosen direction", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/new");
  const fetch = transport(); const good = fetch.getMockImplementation()!;
  fetch.mockImplementation((input, init) => String(input).endsWith("/call-spec-editor-lookups")
    ? reply({ credential_names: {}, telephony_services: [{ key: "office", name: "Office phone" }], mcp_integrations: [] }) : good(input, init));
  render(<App csrfToken="csrf" fetchImpl={fetch} />);
  fireEvent.click(await screen.findByRole("radio", { name: /Outgoing call/ }));
  expect(screen.getByRole("button", { name: "Create call spec" })).toBeDisabled();
  fireEvent.keyDown(screen.getByRole("combobox", { name: "Phone service" }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: "Office phone" }));
  fireEvent.click(screen.getByRole("button", { name: "Create call spec" }));
  await screen.findByRole("button", { name: "More actions" }); writeInitialPrompt(); saveDraft();
  await screen.findByText("Saved as revision 2");
  const submitted = fetch.mock.calls.find(([, init]) => init?.method === "POST");
  const saved = JSON.parse(String(submitted?.[1]?.body)).source;
  expect(saved.incoming_call).toBeUndefined();
  expect(saved.outgoing_call).toEqual({ callee: "caller", handled_by: "assistant" });
  expect(saved.participants.caller.connection).toEqual({ service: "office", mode: "dial", admission: "start_call" });
});

test("outgoing creation explains missing phone services and can be cancelled", async () => {
  window.history.replaceState({}, "", "/admin/tenants/AAAAAAAAAAAAAAAA/call-specs/new");
  render(<App csrfToken="csrf" fetchImpl={transport()} />);
  fireEvent.click(await screen.findByRole("radio", { name: /Outgoing call/ }));
  expect(screen.getByRole("button", { name: "Create call spec" })).toBeDisabled();
  expect(screen.getByRole("link", { name: "Configure a phone service" })).toHaveAttribute("href", "/admin/tenants/AAAAAAAAAAAAAAAA/services");
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(await screen.findByText("No call specs yet")).toBeVisible();
});
