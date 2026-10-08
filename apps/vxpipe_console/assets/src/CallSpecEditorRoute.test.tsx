import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { App } from "./App";
import { modelCatalogFixture } from "./admin/modelCatalogFixtures";
import type { CatalogCapability } from "./admin/modelCatalog";
import { newCallSpec } from "./admin/callSpecEditor/seed";

vi.mock("./admin/callSpecEditor/flow-canvas", () => ({ FlowCanvas: () => <div>Flow canvas</div> }));
afterEach(() => { cleanup(); window.history.replaceState({}, "", "/admin"); });
const source = { ...newCallSpec(modelCatalogFixture).source, name: "Original" };
const stored = { call_spec_id: "hello", revision: 2, latest_revision: 2, published_revision: 1, source };
const reply = (body: unknown, status = 200) => Promise.resolve(new Response(JSON.stringify(body), { status }));
function transport() {
  return vi.fn((input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const url = new URL(String(input), "https://console.test");
    if (url.pathname.endsWith("/call-spec-editor-lookups")) return reply({ credential_names: {}, telephony_services: [], mcp_integrations: [] });
    if (url.pathname.includes("/providers")) {
      const models = modelCatalogFixture[url.searchParams.get("capability") as CatalogCapability] ?? {};
      return url.pathname.endsWith("/models") ? reply({ models: models[url.pathname.split("/").at(-2)!] }) : reply({ providers: Object.keys(models).map((id) => ({ id })) });
    }
    if (init?.method === "POST" || init?.method === "PUT") return reply({ call_spec: stored }, 201);
    if (url.pathname.endsWith("/hello")) return reply({ call_spec: stored });
    if (url.pathname.endsWith("/call-specs")) return reply({ tenant: { key: "demo", name: "Demo" }, call_specs: [], pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 } });
    return reply({}, 404);
  });
}
const fill = (value: string) => fireEvent.change(screen.getByRole("textbox", { name: "Call spec name" }), { target: { value } });

test("new route creates a spec, replaces its URL without losing edits, and publishes saved identity", async () => {
  window.history.replaceState({}, "", "/admin/tenants/demo/call-specs/new");
  const fetch = transport(); render(<App csrfToken="csrf" fetchImpl={fetch} />);
  await screen.findByRole("textbox", { name: "Call spec name" }); fill("New draft");
  fireEvent.click(screen.getByRole("button", { name: "Save draft" }));
  await screen.findByText("Saved as revision 2");
  expect(window.location.pathname).toBe("/admin/tenants/demo/call-specs/hello");
  expect(screen.getByRole("textbox", { name: "Call spec name" })).toHaveValue("New draft");
  fireEvent.click(screen.getByRole("button", { name: "Publish" }));
  await screen.findByText("Published revision 2");
  expect(fetch).toHaveBeenCalledWith("/admin/api/tenants/demo/call-specs/hello/revisions/2/publish", expect.objectContaining({ body: "{}" }));
});

test("session expiry keeps the source and disables writes without navigating away", async () => {
  window.history.replaceState({}, "", "/admin/tenants/demo/call-specs/hello");
  const fetch = transport(); const expired = vi.fn(); render(<App csrfToken="csrf" fetchImpl={fetch} onSessionExpired={expired} />);
  await screen.findByRole("textbox", { name: "Call spec name" }); fill("Keep this draft");
  fetch.mockImplementation(() => reply({}, 401));
  fireEvent.click(screen.getByRole("button", { name: "Save draft" }));
  await screen.findByText(/Your session expired/);
  expect(expired).not.toHaveBeenCalled();
  expect(screen.getByRole("textbox", { name: "Call spec name" })).toHaveValue("Keep this draft");
  expect(screen.getByRole("button", { name: "Save draft" })).toBeDisabled();
});

test("browser back and editor Back use a single discard confirmation", async () => {
  window.history.replaceState({}, "", "/admin/tenants/demo/call-specs");
  window.history.pushState({}, "", "/admin/tenants/demo/call-specs/hello");
  render(<App csrfToken="csrf" fetchImpl={transport()} />);
  await screen.findByRole("textbox", { name: "Call spec name" }); fill("Unsaved");
  fireEvent.click(screen.getByRole("link", { name: "Back to call specs" }));
  fireEvent.click(screen.getByRole("button", { name: "Keep editing" }));
  expect(screen.getByRole("textbox", { name: "Call spec name" })).toHaveValue("Unsaved");
  fireEvent.click(screen.getByRole("link", { name: "Back to call specs" }));
  fireEvent.click(screen.getByRole("button", { name: "Leave page" }));
  await screen.findByText("No call specs yet");
  expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
});

test("explicit revisions are read-only and can open the latest editable revision", async () => {
  window.history.replaceState({}, "", "/admin/tenants/demo/call-specs/hello?revision=1");
  render(<App csrfToken="csrf" fetchImpl={transport()} />);
  await screen.findByText(/Viewing revision/);
  expect(screen.getByRole("button", { name: "Save draft" })).toBeDisabled();
  fireEvent.click(screen.getByRole("link", { name: "Continue editing latest revision" }));
  await waitFor(() => expect(screen.getByRole("button", { name: "Save draft" })).toBeEnabled());
  expect(window.location.search).toBe("");
});

test("failed initial reads show Retry and unmount aborts requests", async () => {
  window.history.replaceState({}, "", "/admin/tenants/demo/call-specs/hello");
  const fetch = transport(); const good = fetch.getMockImplementation()!;
  fetch.mockImplementation((input, init) => String(input).endsWith("/hello") ? reply({}, 503) : good(input, init));
  const view = render(<App csrfToken="csrf" fetchImpl={fetch} />);
  await screen.findByText("Call spec unavailable");
  fetch.mockImplementation(good); fireEvent.click(screen.getByRole("button", { name: "Retry" }));
  await screen.findByRole("textbox", { name: "Call spec name" });
  const signal = fetch.mock.calls.at(-1)?.[1]?.signal;
  act(() => view.unmount()); expect(signal?.aborted).toBe(true);
});

test("browser history back restores the editor until discard is confirmed", async () => {
  window.history.replaceState({}, "", "/admin/tenants/demo/call-specs");
  render(<App csrfToken="csrf" fetchImpl={transport()} />);
  fireEvent.click(await screen.findByRole("link", { name: "New call spec" }));
  await screen.findByRole("textbox", { name: "Call spec name" }); fill("Unsaved history");
  act(() => window.history.back());
  await screen.findByRole("alertdialog");
  fireEvent.click(screen.getByRole("button", { name: "Keep editing" }));
  expect(screen.getByRole("textbox", { name: "Call spec name" })).toHaveValue("Unsaved history");
  await waitFor(() => { expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument(); expect(window.location.pathname).toBe("/admin/tenants/demo/call-specs/new"); });
  act(() => window.history.back());
  await screen.findByRole("alertdialog");
  fireEvent.click(screen.getByRole("button", { name: "Leave page" }));
  await screen.findByText("No call specs yet");
});

test("URL replacement after creation preserves changes made during the request", async () => {
  window.history.replaceState({}, "", "/admin/tenants/demo/call-specs/new");
  const fetch = transport(); const good = fetch.getMockImplementation()!;
  let complete!: (response: Response) => void;
  fetch.mockImplementation((input, init) => init?.method === "POST" ? new Promise((resolve) => { complete = resolve; }) : good(input, init));
  render(<App csrfToken="csrf" fetchImpl={fetch} />);
  await screen.findByRole("textbox", { name: "Call spec name" }); fill("Sent draft");
  fireEvent.click(screen.getByRole("button", { name: "Save draft" }));
  fill("Newer draft");
  await act(async () => complete(await reply({ call_spec: stored }, 201)));
  expect(await screen.findByText("Saved as revision 2")).toBeVisible();
  expect(window.location.pathname).toBe("/admin/tenants/demo/call-specs/hello");
  expect(screen.getByRole("textbox", { name: "Call spec name" })).toHaveValue("Newer draft");
  expect(screen.getByText("Unsaved changes")).toBeVisible();
  expect(screen.getByRole("button", { name: "Publish" })).toBeDisabled();
});
