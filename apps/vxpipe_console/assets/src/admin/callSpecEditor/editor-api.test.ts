import { expect, test, vi } from "vitest";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { catalogCapabilities } from "../modelCatalog";
import { editorFixture } from "./editorFixtures";
import { createEditorApi } from "./editor-api";
import { validateSource } from "./validation";

const reply = (value: unknown, status = 200) => Promise.resolve(new Response(JSON.stringify(value), { status }));
const stored = { call_spec_id: "hello", revision: 2, latest_revision: 3, published_revision: 1, source: editorFixture.source };

test("reads immutable source and historical metadata with scoped, abortable requests", async () => {
  const fetch = vi.fn(() => reply({ call_spec: stored }));
  const api = createEditorApi("tenant / one", "csrf", fetch);
  const signal = new AbortController().signal;
  const snapshot = await api.read("hello", signal, 2);
  expect(snapshot.document.source).toEqual(editorFixture.source);
  expect(snapshot.document.readOnly).toBe(true);
  expect(snapshot.saved).toEqual({ callSpecId: "hello", revision: 2, publishedRevision: 1 });
  expect(fetch).toHaveBeenCalledWith("/admin/api/tenants/tenant%20%2F%20one/call-specs/hello?revision=2", expect.objectContaining({ signal, credentials: "same-origin", cache: "no-store" }));
});

test("create, append and publish use exact bodies and CSRF; failures retain field paths", async () => {
  const fetch = vi.fn(() => reply({ call_spec: stored }, 201));
  const api = createEditorApi("tenant", "csrf", fetch);
  const signal = new AbortController().signal;
  const request = { id: 1, action: "save" as const, source: editorFixture.source };
  expect(await api.execute(request, signal)).toEqual({ status: 201, callSpecId: "hello", revision: 2 });
  expect(fetch).toHaveBeenLastCalledWith("/admin/api/tenants/tenant/call-specs", expect.objectContaining({ method: "POST", headers: expect.objectContaining({ "x-csrf-token": "csrf" }), body: JSON.stringify({ source: editorFixture.source }) }));
  await api.execute({ ...request, callSpecId: "hello" }, signal);
  expect(fetch).toHaveBeenLastCalledWith(expect.stringContaining("/call-specs/hello"), expect.objectContaining({ method: "PUT" }));
  await api.execute({ ...request, action: "publish", callSpecId: "hello", revision: 2 }, signal);
  expect(fetch).toHaveBeenLastCalledWith(expect.stringContaining("/hello/revisions/2/publish"), expect.objectContaining({ method: "POST", body: "{}" }));
  const error = { code: "invalid_call_spec", path: ["participants", "intake", "prompt"], reason: "required" };
  fetch.mockImplementation(() => reply({ error }, 422));
  expect(await api.execute(request, signal)).toEqual({ status: 422, error });
  fetch.mockImplementation(() => reply({}, 401));
  expect(await api.execute(request, signal)).toEqual({ status: 401 });
  fetch.mockImplementation(() => reply({ call_spec: { revision: 2 } }, 201));
  await expect(api.execute(request, signal)).rejects.toThrow();
});

test("loads installed provider/model listings and safe named lookups without live discovery", async () => {
  const fetch = vi.fn((input: RequestInfo | URL) => {
    const url = new URL(String(input), "https://console.test");
    const capability = url.searchParams.get("capability") as typeof catalogCapabilities[number];
    const providers = modelCatalogFixture[capability] ?? {};
    if (url.pathname.endsWith("/call-spec-editor-lookups")) return reply({ credential_names: { google: ["primary"] }, telephony_services: [{ key: "phone", name: "phone" }], mcp_integrations: ["help"] });
    if (url.pathname.endsWith("/models")) return reply({ models: providers[url.pathname.split("/").at(-2)!] });
    return reply({ providers: Object.keys(providers).map((id) => ({ id })) });
  });
  const api = createEditorApi("tenant", "csrf", fetch);
  const signal = new AbortController().signal;
  expect(await api.catalog(signal)).toEqual(Object.fromEntries(catalogCapabilities.map((capability) => [capability, modelCatalogFixture[capability] ?? {}])));
  expect(await api.lookups(signal)).toEqual({ credentialNames: { google: ["primary"] }, telephonyServices: [{ key: "phone", name: "phone" }], mcpIntegrations: ["help"] });
});

test("a no-op editor save preserves an API-authored integer enum beyond Number precision", async () => {
  const source = {
    ...editorFixture.source,
    call_variables: { sections: { ...editorFixture.source.call_variables?.sections, account: { schema: {
      type: "object", properties: { external_id: { type: "integer", enum: ["EXACT_INTEGER"] } },
    } } } },
  };
  // Use the actual JSON spelling returned by the server, not an already rounded JS number.
  const response = JSON.stringify({ call_spec: { ...stored, source } })
    .replace('"EXACT_INTEGER"', "9007199254740993");
  const fetch = vi.fn((_input: RequestInfo | URL, init?: RequestInit) =>
    init?.method === "PUT" ? reply({ call_spec: stored }, 201) : Promise.resolve(new Response(response)));
  const api = createEditorApi("tenant", "csrf", fetch);
  const signal = new AbortController().signal;
  const snapshot = await api.read("hello", signal);
  expect(validateSource(snapshot.document.source)).toEqual([]);
  await api.execute({ id: 1, action: "save", callSpecId: "hello", source: snapshot.document.source }, signal);

  expect(fetch.mock.calls.at(-1)?.[1]?.body).toContain('"enum":[9007199254740993]');
});
