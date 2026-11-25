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
  expect(fetch).toHaveBeenCalledWith("/api/tenants/tenant%20%2F%20one/call-specs/hello?revision=2", expect.objectContaining({ signal, credentials: "same-origin", cache: "no-store" }));
});

test("create, append and publish use exact bodies and CSRF; failures retain field paths", async () => {
  const fetch = vi.fn(() => reply({ call_spec: stored }, 201));
  const api = createEditorApi("tenant", "csrf", fetch);
  const signal = new AbortController().signal;
  const request = { id: 1, action: "save" as const, source: editorFixture.source };
  expect(await api.execute(request, signal)).toEqual({ status: 201, callSpecId: "hello", revision: 2 });
  expect(fetch).toHaveBeenLastCalledWith("/api/tenants/tenant/call-specs", expect.objectContaining({ method: "POST", headers: expect.objectContaining({ "x-csrf-token": "csrf" }), body: JSON.stringify({ source: editorFixture.source }) }));
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

test("loads configured provider/model listings and safe named lookups without live discovery", async () => {
  const fetch = vi.fn((input: RequestInfo | URL) => {
    const url = new URL(String(input), "https://console.test");
    const capability = url.searchParams.get("capability") as typeof catalogCapabilities[number];
    const providers = modelCatalogFixture[capability] ?? {};
    if (url.pathname.endsWith("/call-spec-editor-lookups")) return reply({ credential_names: { google: ["primary"] }, telephony_services: [{ key: "phone", name: "phone" }], mcp_integrations: ["help"], tool_catalog: { mcp_available: true, tools: [{ type: "platform", tool: "hangup", description: "End the call." }] } });
    if (url.pathname.endsWith("/models")) return reply({ models: providers[url.pathname.split("/").at(-2)!] });
    return reply({ providers: Object.keys(providers).map((id) => ({ id, credential_available: true })) });
  });
  const api = createEditorApi("tenant", "csrf", fetch);
  const signal = new AbortController().signal;
  expect(await api.catalog(signal)).toEqual(Object.fromEntries(catalogCapabilities.map((capability) => [capability, modelCatalogFixture[capability] ?? {}])));
  expect(fetch.mock.calls.every(([url]) => String(url).startsWith("/api/tenants/tenant/providers"))).toBe(true);
  expect(await api.lookups(signal)).toEqual({ credentialNames: { google: ["primary"] }, telephonyServices: [{ key: "phone", name: "phone" }], mcpIntegrations: ["help"], toolCatalog: { mcpAvailable: true, tools: [{ type: "platform", tool: "hangup", description: "End the call." }] } });
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

test("phone inventory uses a scoped abortable request with server search, pagination and current-spec exclusion", async () => {
  const fetch = vi.fn(() => reply({ numbers: [{ id: "1", number: "+15550001000", name: "Office", available: false, assigned_to: ["Reception"] }], next_page: "next" }));
  const signal = new AbortController().signal;
  const result = await createEditorApi("tenant", "csrf", fetch).phoneNumbers("office / phone", "555", "page-token", signal, "current");
  expect(result).toEqual({ numbers: [{ id: "1", number: "+15550001000", name: "Office", available: false, assignedTo: ["Reception"] }], nextPage: "next" });
  expect(fetch).toHaveBeenCalledWith("/api/tenants/tenant/telephony-services/office%20%2F%20phone/numbers?search=555&page=page-token&call_spec_id=current", expect.objectContaining({ signal, credentials: "same-origin", cache: "no-store" }));
});

test("model choices exclude unconfigured or unavailable providers before fetching models", async () => {
  const fetch = vi.fn((input: RequestInfo | URL) => {
    const url = new URL(String(input), "https://console.test");
    const capability = url.searchParams.get("capability");
    if (url.pathname.endsWith("/models")) return reply({ models: modelCatalogFixture.text_to_speech!.elevenlabs });
    return reply({ providers: capability === "text_to_speech" ? [
      { id: "elevenlabs", credential_available: true }, { id: "cartesia", credential_available: false }, { id: "deepgram" },
    ] : [] });
  });
  const catalog = await createEditorApi("tenant", "csrf", fetch).catalog(new AbortController().signal);
  expect(Object.keys(catalog.text_to_speech!)).toEqual(["elevenlabs"]);
  expect(fetch.mock.calls.filter(([path]) => String(path).includes("/models"))).toHaveLength(1);
});

test("reads and writes publication metadata independently from immutable revision IDs", async () => {
  const publication = { version: 2, revision: 7, unpublished_changes: false, draft_saved_at: "2026-11-17T12:00:00Z",
    history: [{ version: 2, published_at: "2026-11-17T11:00:00Z" }] };
  const fetch = vi.fn(() => reply({ call_spec: { ...stored, revision: 9, latest_revision: 9, published_revision: 7, publication } }));
  const api = createEditorApi("tenant", "csrf", fetch);
  const signal = new AbortController().signal;
  const snapshot = await api.read("hello", signal);
  expect(snapshot.saved?.publication).toEqual({ version: 2, revision: 7, unpublishedChanges: false, draftSavedAt: "2026-11-17T12:00:00Z",
    history: [{ version: 2, publishedAt: "2026-11-17T11:00:00Z" }] });
  const result = await api.execute({ id: 1, action: "publish", source: snapshot.document.source, callSpecId: "hello", revision: 9 }, signal);
  expect(result.revision).toBe(9);
  expect(result.publication).toEqual(snapshot.saved?.publication);
});

test("only the latest directional draft offers the Entry upgrade", async () => {
  const source = { ...editorFixture.source, schema_version: "20261004.01" };
  const api = createEditorApi("tenant", "csrf", () => reply({ call_spec: { ...stored, latest_revision: stored.revision, source } }));
  const signal = new AbortController().signal;
  expect((await api.read("hello", signal)).document).toMatchObject({ readOnly: true, canUpgradeEntry: true, source });
  const history = await api.read("hello", signal, stored.revision);
  expect(history.document.readOnly).toBe(true);
  expect(history.document.canUpgradeEntry).toBeUndefined();
});

test("historical revisions with Entry overrides direct the reader to the full call spec JSON", async () => {
  const source = structuredClone(editorFixture.source);
  source.schema_version = "20261004.01";
  source.participants.caller!.while_present = { record_audio: false };
  const api = createEditorApi("tenant", "csrf", () => reply({ call_spec: { ...stored, source } }));
  const snapshot = await api.read("hello", new AbortController().signal, stored.revision);
  expect(snapshot.document.notice).toContain("View the saved Entry overrides in the call spec JSON");
});
