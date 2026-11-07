import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter, useLocation } from "react-router";
import { useState } from "react";
import { afterEach, expect, test, vi } from "vitest";
import { IntegrationsApp } from "../../IntegrationsApp";
import { saveOAuthDraft } from "./oauthDraft";

afterEach(() => { cleanup(); sessionStorage.clear(); });
const endpoint = "https://mcp.example.test/mcp";
const identity = { actorId: "actor", tenantKey: "tenant-a", attemptId: "attempt" };
const returnTo = "/t/tenant-a/services/search?q=calendar&cursor=page";
const saved = { id: "connection", tenant_key: "tenant-a", endpoint, server_name: "Calendar tools", auth_method: "oauth", generation: 2, status: "connected", tool_count: 0, can_edit: true };
const prepare = (extra = {}) => saveOAuthDraft({ ...identity, connectionId: "connection", returnTo, draft: { endpoint, method: "dcr", ...extra } });
function Location() { const location = useLocation(); return <output aria-label="Current location">{location.pathname}{location.search}</output>; }
function fixture(connected = false) {
  return vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    if (String(url).endsWith("/categories")) return Response.json({ categories: [] });
    const body = init?.body ? JSON.parse(String(init.body)) : {};
    if (String(url).endsWith("/mcp-discovery")) return Response.json({ discovery: { ...body, outcome: "oauth", suggested_method: "cimd",
      supported_grants: ["authorization_code"], issuers: ["https://auth.example.test"],
      oauth_client: { callback_url: "https://console.example.test/oauth/mcp/callback", client_id: "https://console.example.test/oauth/client-metadata.json" },
      oauth: { issuer: "https://auth.example.test", authorization_endpoint: "https://auth.example.test/authorize", token_endpoint: "https://auth.example.test/token",
        registration_endpoint: "https://auth.example.test/register", client_id_metadata_document_supported: true, token_endpoint_auth_methods_supported: ["none"] } } });
    if (String(url).endsWith("/mcp-oauth")) return Response.json({ authorization_url: "https://auth.example.test/authorize?state=opaque", attempt_id: "attempt", connection_id: "connection" });
    return Response.json({ tenant: { key: "tenant-a", name: "Tenant A" }, installation_version: "0.1.0", directory_status: "local", connections: [],
      mcp_connections: connected ? [saved] : [], page: null, local_items: [], fallback_items: [] });
  });
}
function mount(path: string, fetchImpl = fixture(), actorId = "actor", redirect = vi.fn()) {
  return render(<MemoryRouter initialEntries={[path]}><Location /><IntegrationsApp actorId={actorId} scope={{ kind: "tenant", tenantKey: "tenant-a", tenantName: "Tenant A" }}
    canManageMcps csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={vi.fn()} onAuthorizationRedirect={redirect} /></MemoryRouter>);
}

test("production handoff keeps the directory location and saves only a matching nonsecret draft", async () => {
  const fetchImpl = fixture(); const redirect = vi.fn();
  mount(returnTo, fetchImpl, "actor", redirect);
  fireEvent.click(await screen.findByRole("button", { name: "Connect other MCP" }));
  fireEvent.change(screen.getByLabelText("MCP server URL"), { target: { value: endpoint } });
  await waitFor(() => expect(screen.getByLabelText("Authentication Type")).toHaveValue("cimd"));
  fireEvent.change(screen.getByLabelText("Authentication Type"), { target: { value: "dcr" } });
  fireEvent.change(screen.getByLabelText("Initial registration token"), { target: { value: "synthetic-secret" } });
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await waitFor(() => expect(redirect).toHaveBeenCalledWith("https://auth.example.test/authorize?state=opaque"));
  const request = fetchImpl.mock.calls.find(([url]) => String(url).endsWith("/mcp-oauth"));
  expect(JSON.parse(String(request?.[1]?.body))).toHaveProperty("return_to", returnTo);
  const draft = sessionStorage.getItem("vxpipe.mcp.oauth")!;
  expect(JSON.parse(draft)).toMatchObject({ ...identity, returnTo, connectionId: "connection", draft: { endpoint, method: "dcr" } });
  expect(draft).not.toMatch(/synthetic-secret|authorization_url|state=opaque/);
});

test.each(["denied", "failed"])("%s restores the matched form once, preserves location and requires secret reentry", async status => {
  prepare();
  mount(`${returnTo}&mcp=${status}&mcp_attempt=attempt`);
  expect(await screen.findByRole("dialog")).toBeVisible();
  expect(screen.getByLabelText("MCP server URL")).toHaveValue(endpoint);
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("dcr");
  expect(screen.getByLabelText("Initial registration token")).toHaveValue("");
  expect(within(screen.getByRole("dialog")).getByText(/Enter any credentials again/)).toBeVisible();
  await waitFor(() => expect(screen.getByLabelText("Current location").textContent).toBe(returnTo));
  expect(screen.getByLabelText("Current location")).not.toHaveTextContent("mcp_attempt");
  expect(sessionStorage.getItem("vxpipe.mcp.oauth")).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

test.each([false, true])("callback success is confirmed from current authorized inventory: %s", async connected => {
  prepare(); mount(`${returnTo}&mcp=connected&mcp_attempt=attempt`, fixture(connected));
  if (connected) expect(await screen.findByText("Calendar tools connected.")).toBeVisible();
  else expect(await screen.findByText(/Could not confirm the connection/)).toBeVisible();
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

test("another actor or attempt cannot restore a draft or report OAuth success", async () => {
  prepare(); mount(`${returnTo}&mcp=connected&mcp_attempt=attempt`, fixture(true), "other-actor");
  expect(await screen.findByText(/No matching sign-in attempt/)).toBeVisible();
  expect(screen.queryByText("Calendar tools connected.")).not.toBeInTheDocument();
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

test("a changed saved connection is not silently replaced with an old draft", async () => {
  prepare({ generation: 1 }); mount(`${returnTo}&mcp=denied&mcp_attempt=attempt`, fixture(true));
  expect(await screen.findByText(/connection changed while you were signing in/)).toBeVisible();
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

test.each(["denied", "failed"])("%s recovers a disconnected record through a fresh generation-bound read", async status => {
  prepare({ generation: 2 });
  const fresh = fixture();
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => String(url).includes("/mcp-connections/")
    ? Response.json({ connection: { ...saved, status: "revoked" } }) : fresh(url, init));
  mount(`${returnTo}&mcp=${status}&mcp_attempt=attempt`, fetchImpl);
  const dialog = await screen.findByRole("dialog");
  expect(within(dialog).getByRole("button", { name: "Reconnect" })).toBeVisible();
  expect(screen.getByLabelText("MCP server URL")).toBeDisabled();
  expect(screen.getByLabelText("Initial registration token")).toHaveValue("");
  expect(fetchImpl.mock.calls.filter(([url]) => String(url).includes("/mcp-connections/"))).toHaveLength(1);
  expect(fetchImpl.mock.calls.some(([url]) => String(url).endsWith("/connection?retained_generation=2"))).toBe(true);
  expect(fetchImpl.mock.calls.some(([url]) => /\/(?:mcp-oauth|oauth|reconnect)$/.test(String(url)))).toBe(false);
  await waitFor(() => expect(screen.getByLabelText("Current location").textContent).toBe(returnTo));
});

test("retained return recovery can retry a temporary outage without losing its consumed public draft", async () => {
  prepare({ generation: 2 }); const fresh = fixture(); let unavailable = true;
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => String(url).includes("/mcp-connections/")
    ? unavailable ? new Response(null, { status: 503 }) : Response.json({ connection: { ...saved, status: "revoked" } }) : fresh(url, init));
  mount(`${returnTo}&mcp=denied&mcp_attempt=attempt`, fetchImpl);
  const retry = await screen.findByRole("button", { name: "Retry recovery" });
  expect(sessionStorage.getItem("vxpipe.mcp.oauth")).toBeNull();
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  unavailable = false; fireEvent.click(retry);
  expect(await screen.findByRole("dialog")).toBeVisible();
  expect(screen.getByRole("button", { name: "Reconnect" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Retry recovery" })).not.toBeInTheDocument();
});

test("leaving a failed retained recovery removes its stale retry action", async () => {
  prepare({ generation: 2 }); const fresh = fixture();
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => String(url).includes("/mcp-connections/")
    ? new Response(null, { status: 503 }) : fresh(url, init));
  mount(`${returnTo}&mcp=denied&mcp_attempt=attempt`, fetchImpl);
  await screen.findByRole("button", { name: "Retry recovery" });
  fireEvent.click(screen.getByRole("link", { name: "AI models" }));
  await waitFor(() => expect(screen.queryByRole("button", { name: "Retry recovery" })).not.toBeInTheDocument());
  expect(screen.queryByText(/Could not load the disconnected connection/)).not.toBeInTheDocument();
});

test.each([{ generation: 3 }, { tenant_key: "other" }, { endpoint: "https://other.test/mcp" }, { can_edit: false }])(
  "retained return metadata is checked before restoring: %j", async changes => {
    prepare({ generation: 2 }); const fresh = fixture();
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => String(url).includes("/mcp-connections/")
      ? Response.json({ connection: { ...saved, status: "revoked", ...changes } }) : fresh(url, init));
    mount(`${returnTo}&mcp=denied&mcp_attempt=attempt`, fetchImpl);
    expect(await screen.findByText(/connection changed while you were signing in/)).toBeVisible();
    expect(fetchImpl.mock.calls.some(([url]) => String(url).includes("retained_generation=2"))).toBe(true);
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

test("retained metadata arriving after an actor change cannot reopen the old actor's form", async () => {
  prepare({ generation: 2 }); const fresh = fixture(); let release!: (value: Response) => void;
  const pending = new Promise<Response>(resolve => { release = resolve; });
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => String(url).includes("/mcp-connections/") ? pending : fresh(url, init));
  function ChangingActor() {
    const [actorId, setActorId] = useState("actor");
    return <><button onClick={() => setActorId("other-actor")}>Change actor</button><IntegrationsApp actorId={actorId} scope={{ kind: "tenant", tenantKey: "tenant-a", tenantName: "Tenant A" }}
      canManageMcps csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={vi.fn()} /></>;
  }
  render(<MemoryRouter initialEntries={[`${returnTo}&mcp=denied&mcp_attempt=attempt`]}><ChangingActor /></MemoryRouter>);
  await waitFor(() => expect(fetchImpl.mock.calls.some(([url]) => String(url).includes("retained_generation=2"))).toBe(true));
  fireEvent.click(screen.getByRole("button", { name: "Change actor" }));
  release(Response.json({ connection: { ...saved, status: "revoked" } }));
  await screen.findByText(/No matching sign-in attempt/);
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

test("a denied listed handoff restores the fixed listing and revalidates it before retry", async () => {
  const entry = { directory_id: "directory", integration_id: "calendar", revision: 1, name: "Calendar", endpoint,
    authentication: { type: "oauth2" as const, registration: "dcr" as const } };
  const reference = { directory_id: "directory", integration_id: "calendar", entry_revision: 1, page: { scope: "tenant" as const, limit: 20 } };
  prepare({ listing: { reference, entry } });
  const fresh = fixture();
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
    const response = await fresh(url, init);
    if (!String(url).endsWith("/mcp-discovery")) return response;
    const body = await response.json();
    return Response.json({ discovery: { ...body.discovery, endpoint, listing: entry, resource: { resource: endpoint } } });
  });
  const redirect = vi.fn();
  mount(`${returnTo}&mcp=denied&mcp_attempt=attempt`, fetchImpl, "actor", redirect);
  await screen.findByRole("dialog", { name: "Connect Calendar" });
  expect(screen.queryByLabelText("MCP server URL")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Authentication Type")).not.toBeInTheDocument();
  await screen.findByText("OAuth settings discovered.");
  expect(screen.getByLabelText("Initial registration token")).toHaveValue("");
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await waitFor(() => expect(redirect).toHaveBeenCalledOnce());
  const request = fetchImpl.mock.calls.find(([url]) => String(url).endsWith("/mcp-oauth"));
  expect(JSON.parse(String(request?.[1]?.body))).toEqual({ listing: reference, revision: "0", return_to: returnTo });
});

test.each(["invalid_cursor", "cursor_expired"])("callback draft survives directory cursor recovery: %s", async code => {
  prepare(); const fresh = fixture();
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => String(url).includes("cursor=")
    ? Response.json({ error: { code } }, { status: code === "invalid_cursor" ? 400 : 410 }) : fresh(url, init));
  mount(`${returnTo}&mcp=denied&mcp_attempt=attempt`, fetchImpl);
  fireEvent.click(await screen.findByRole("button", { name: "Start from first page" }));
  expect(await screen.findByRole("dialog")).toBeVisible();
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("dcr");
  expect(screen.getByLabelText("Current location")).toHaveTextContent("/t/tenant-a/services/search?q=calendar");
  expect(screen.getByLabelText("Current location")).not.toHaveTextContent("cursor");
});

test("cursor recovery retains callback context while the authenticated actor is loading", async () => {
  prepare(); const fresh = fixture();
  const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => String(url).includes("cursor=")
    ? Response.json({ error: { code: "invalid_cursor" } }, { status: 400 }) : fresh(url, init));
  function SessionLoading() {
    const [actorId, setActorId] = useState<string>();
    return <><button onClick={() => setActorId("actor")}>Load identity</button><IntegrationsApp actorId={actorId} scope={{ kind: "tenant", tenantKey: "tenant-a", tenantName: "Tenant A" }}
      canManageMcps={!!actorId} csrfToken="csrf" fetchImpl={fetchImpl} onNavigate={vi.fn()} /></>;
  }
  render(<MemoryRouter initialEntries={[`${returnTo}&mcp=denied&mcp_attempt=attempt`]}><SessionLoading /></MemoryRouter>);
  fireEvent.click(await screen.findByRole("button", { name: "Start from first page" }));
  await screen.findByText("No matching integrations");
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Load identity" }));
  expect(await screen.findByRole("dialog")).toBeVisible();
  expect(screen.getByLabelText("Authentication Type")).toHaveValue("dcr");
});
