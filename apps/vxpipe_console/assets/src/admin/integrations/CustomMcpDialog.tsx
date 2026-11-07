import { useEffect, useRef, useState } from "react";
import { ArrowRight, LoaderCircle, RefreshCw } from "lucide-react";
import { Button } from "../Button";
import { SetupDialog } from "../SetupDialog";
import { Disclosure, Pairs, SelectField, TextField } from "../mcpStories/FormControls";
import { useMcpDiscovery } from "./useMcpDiscovery";
import { validMcpUrl } from "./mcpDiscoveryApi";
import { OAuthFields } from "./OAuthFields";
import type { OAuthDraft } from "./oauthDraft";
import { oauthDefaults, oauthProblem, oauthRequest, type ClientAuthentication, type OAuthGrant, type OAuthMethod, type OAuthValues } from "./oauthForm";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../components/ui/tabs";
import type { McpConnection } from "./inventoryApi";
import { listedMethod, type McpListing } from "./listedMcp";
import { listedOAuthMethod, listedOAuthRequest } from "./listedOAuthForm";
import { conflictUrl, parseConflictConnection, parseMcpConflict, type McpConflict } from "./mcpConflict";
import type { IntegrationFetch } from "./useInventory";
import "../mcpStories/mcp-services-story.css";

type Method = "" | "none" | "bearer" | "headers" | "basic" | OAuthMethod;
type Header = { id: number; name: string; value: string };
type SavedOAuth = { registrationMethod: OAuthMethod; grant: OAuthGrant; clientAuth: ClientAuthentication };
export type OAuthHandoff = { authorizationUrl: string; attemptId: string; connectionId: string };
const authorize = (handoff: OAuthHandoff) => window.location.assign(handoff.authorizationUrl);
export function CustomMcpDialog({ tenantKey, csrfToken, fetchImpl, onSessionExpired, onClose, onConnected, connection, listing, onAuthorize = authorize, returnTo, initialDraft, recoveryNotice, onOpenConnection }: {
  connection?: McpConnection; tenantKey: string; csrfToken: string; fetchImpl: IntegrationFetch; onSessionExpired: () => void;
  listing?: McpListing;
  onClose: () => void; onConnected: () => void;
  onAuthorize?: (handoff: OAuthHandoff, draft: OAuthDraft) => void; returnTo?: string; initialDraft?: OAuthDraft; recoveryNotice?: string;
  onOpenConnection?: (connection: McpConnection) => void;
}) {
  const currentListing = listing ?? initialDraft?.listing;
  const reconnecting = connection?.status === "revoked";
  const directoryEntry = connection?.directoryEntry ?? currentListing?.entry;
  const listedOAuth = directoryEntry?.authentication.type === "oauth2";
  const [endpoint, setEndpoint] = useState(directoryEntry?.endpoint ?? initialDraft?.endpoint ?? connection?.endpoint ?? "");
  const [revision, setRevision] = useState(0);
  const [method, setMethod] = useState<Method>(initialDraft?.method ?? (connection?.authMethod === "oauth" ? "" : connection?.authMethod ?? "") as Method);
  const [issuer, setIssuer] = useState<string | undefined>(initialDraft?.issuer);
  const [manualIssuer, setManualIssuer] = useState(false);
  const [token, setToken] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [headers, setHeaders] = useState<Header[]>([]);
  const [oauthEdits, setOAuthEdits] = useState<Partial<OAuthValues>>(initialDraft ? { grant: "authorization_code", ...(initialDraft.clientAuth ? { clientAuth: initialDraft.clientAuth } : {}) } : {});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [conflict, setConflict] = useState<McpConflict | null>(null);
  const [saved, setSaved] = useState(connection);
  const [savedOAuth, setSavedOAuth] = useState<SavedOAuth | null>(null);
  const [replaceCredentials, setReplaceCredentials] = useState(!connection || reconnecting || !!initialDraft);
  const [tools, setTools] = useState<string[]>([]);
  const [toolsStatus, setToolsStatus] = useState("loading");
  const [toolsRevision, setToolsRevision] = useState(0);
  const [tab, setTab] = useState("authentication");
  const [search, setSearch] = useState("");
  const readOnly = connection?.canEdit === false;
  const connectionUrl = `/api/tenants/${encodeURIComponent(tenantKey)}/mcp-connections${connection ? `/${encodeURIComponent(connection.id)}` : ""}`;
  useEffect(() => {
    if (!connection || reconnecting) return;
    const controller = new AbortController();
    setToolsStatus("loading");
    fetchImpl(connectionUrl, { credentials: "same-origin", headers: { accept: "application/json" }, signal: controller.signal })
      .then(async response => {
        if (controller.signal.aborted) return;
        if (response.status === 401) { onSessionExpired(); return; }
        if (!response.ok) throw new Error("Details unavailable");
        const body = await response.json();
        if (body?.connection?.id !== connection.id || !Array.isArray(body.connection.tools) ||
          !body.connection.tools.every((tool: unknown) => !!tool && typeof tool === "object" && "name" in tool && typeof tool.name === "string")) throw new Error("Invalid tools");
        if (!controller.signal.aborted) { setTools(body.connection.tools.map((tool: { name: string }) => tool.name)); setSavedOAuth(parseSavedOAuth(body.connection.oauth)); setToolsStatus("ready"); }
      }).catch(() => { if (!controller.signal.aborted) setToolsStatus("failed"); });
    return () => controller.abort();
  }, [connection, connectionUrl, fetchImpl, onSessionExpired, toolsRevision, reconnecting]);
  const pending = useRef<AbortController | null>(null);
  useEffect(() => () => pending.current?.abort(), []);
  const discovery = useMcpDiscovery({ tenantKey, csrfToken, endpoint, revision: String(revision), issuer,
    ...(!saved && currentListing ? { listing: currentListing.reference } : {}),
    ...(saved && listedOAuth ? { connection: { connection_id: saved.id, generation: saved.generation } } : {}),
    active: !readOnly && (listedOAuth ? !saved || replaceCredentials : !directoryEntry && (!saved || endpoint !== saved.endpoint || (replaceCredentials && (saved.authMethod === "oauth" || ["cimd", "dcr", "own_client"].includes(method))))), fetchImpl, onSessionExpired });
  const savedMethod: Method = saved?.authMethod === "oauth" ? savedOAuth?.registrationMethod ?? "" : (saved?.authMethod ?? "") as Method;
  const selected = directoryEntry ? listedOAuth ? saved && !replaceCredentials ? savedMethod : listedOAuthMethod(discovery.data?.listing ?? directoryEntry, discovery.data) : listedMethod(directoryEntry) : method || (endpoint === saved?.endpoint ? savedMethod : "") || discovery.data?.suggestedMethod || "";
  const apiKeyHeader = directoryEntry?.authentication.type === "api_key" ? directoryEntry.authentication.header_name : null;
  const oauthMethod = selected === "cimd" || selected === "dcr" || selected === "own_client" ? selected : null;
  const oauthValues = { ...oauthDefaults(endpoint, discovery.data), ...oauthEdits, ...(listedOAuth ? { grant: "authorization_code" as const } : {}) };
  const clientAuthConfirmed = !listedOAuth || oauthEdits.clientAuth !== undefined;
  const reuseRegistration = !!(listedOAuth && discovery.data?.oauthRegistration?.reusable);

  function clearCredentials() { setToken(""); setUsername(""); setPassword(""); setHeaders([]); setOAuthEdits({}); }
  function changeUrl(value: string) {
    setReplaceCredentials(true); setEndpoint(value); setRevision(value => value + 1); setIssuer(undefined); setMethod(""); clearCredentials(); setError(""); setConflict(null);
  }
  function changeMethod(value: string) {
    if (value === selected) return;
    setReplaceCredentials(true); setMethod(value as Method); clearCredentials(); setError(""); setConflict(null);
    if (value === "headers") setHeaders([{ id: 1, name: "X-API-Key", value: "" }]);
  }
  function changeIssuer(value: string) { setIssuer(value || undefined); clearCredentials(); setError(""); setConflict(null); }
  function replaceSavedCredentials(value: boolean) {
    setReplaceCredentials(value); clearCredentials();
    if (value && savedOAuth) setOAuthEdits({ grant: savedOAuth.grant, clientAuth: savedOAuth.clientAuth });
  }
  async function connect(catalogOnly = false) {
    if (catalogOnly && reconnecting) return;
    const refreshTools = catalogOnly || !!(saved?.authMethod === "oauth" && !replaceCredentials && endpoint === saved.endpoint);
    if (readOnly || busy || (!refreshTools && (!selected || !validMcpUrl(endpoint)))) return;
    if (!refreshTools && oauthMethod) {
      if (listedOAuth && oauthMethod === "own_client" && !clientAuthConfirmed) { setError("Choose the authentication method used when this OAuth client was registered."); return; }
      const problem = reuseRegistration && oauthMethod === "dcr" && discovery.data?.oauthClient ? null : oauthProblem(oauthMethod, oauthValues, discovery.data);
      if (problem) { setError(problem); return; }
    }
    if (!refreshTools && replaceCredentials && ((selected === "bearer" && !token) || (selected === "basic" && (!username || !password)) ||
      (selected === "headers" && (apiKeyHeader ? !token : !headers.length)) || headers.some(header => !header.name || !header.value))) {
      setError("Complete the credentials for the selected authentication type."); return;
    }
    const extra = headers.length ? { headers: headers.map(({ name, value }) => ({ name, value })) } : {};
    const credentials = selected === "none" ? {} : selected === "bearer" ? { token, ...extra } : selected === "basic" ? { username, password, ...extra } : apiKeyHeader ? { headers: [{ value: token }] } : extra;
    const browserOAuth = !refreshTools && oauthMethod && (oauthMethod !== "own_client" || oauthValues.grant === "authorization_code");
    if (browserOAuth && saved && endpoint !== saved.endpoint) {
      setError("To use a different server URL with OAuth, connect it as a new MCP."); return;
    }
    const requestUrl = browserOAuth ? saved ? `${connectionUrl}/oauth` : `/api/tenants/${encodeURIComponent(tenantKey)}/mcp-oauth` : reconnecting ? `${connectionUrl}/reconnect` : connectionUrl;
    const requestBody = refreshTools && saved ? { generation: saved.generation, refresh_tools: true } : oauthMethod ? {
      ...(listedOAuth ? listedOAuthRequest(oauthMethod, String(revision), reuseRegistration ? { ...oauthValues, initialAccessToken: "" } : oauthValues, issuer, saved ? undefined : currentListing?.reference) : oauthRequest(oauthMethod, endpoint, String(revision), oauthValues, issuer)),
      ...(saved ? { generation: saved.generation } : {}), ...(browserOAuth && returnTo ? { return_to: returnTo } : {}),
    } : { ...(directoryEntry ? (!saved && currentListing ? { listing: currentListing.reference } : {}) : { endpoint, auth_method: selected }),
      ...(replaceCredentials ? { credentials } : {}), ...(saved ? { generation: saved.generation } : {}) };
    const controller = new AbortController(); pending.current = controller;
    setBusy(true); setError(""); setConflict(null);
    try {
      const response = await fetchImpl(requestUrl, {
        method: browserOAuth || reconnecting ? "POST" : saved ? "PATCH" : "POST", credentials: "same-origin", signal: controller.signal,
        headers: { accept: "application/json", "content-type": "application/json", "x-csrf-token": csrfToken },
        body: JSON.stringify(requestBody),
      });
      if (controller.signal.aborted) return;
      if (response.status === 401) { onSessionExpired(); return; }
      if (!response.ok) {
        const errorBody = await response.json().catch(() => null);
        if (controller.signal.aborted) return;
        if (response.status === 429) { setError("Connection is busy. Wait a moment, then retry."); return; }
        const proposal = response.status === 409 && !saved && onOpenConnection ? parseMcpConflict(errorBody) : null;
        if (proposal) { setConflict(proposal); return; }
        if (currentListing && !saved) {
          if (["mcp_listing_unavailable", "invalid_mcp_listing"].includes(errorBody?.error?.code)) {
            setError("This directory entry changed or is unavailable. Close this dialog and select it again from the directory."); return;
          }
        }
        setError(response.status === 409 && saved ? "This connection changed since you opened it. Close and reopen to load the latest settings." : response.status === 409 ? "This server is already connected. Close this dialog to manage its connection." : "Could not connect. Check the credentials and retry."); return;
      }
      const body = await response.json();
      if (browserOAuth) {
        const handoff = parseHandoff(body);
        if (!controller.signal.aborted) {
          const draft: OAuthDraft = { endpoint, method: oauthMethod!, ...(issuer ? { issuer } : {}),
            ...(oauthMethod === "own_client" ? { clientAuth: oauthValues.clientAuth } : {}), ...(saved ? { generation: saved.generation } : {}),
            ...(!saved && currentListing ? { listing: currentListing } : {}) };
          clearCredentials(); onAuthorize(handoff, draft);
        }
        return;
      }
      if (typeof body?.connection?.id !== "string" || typeof body?.connection?.generation !== "number") throw new Error("Invalid connection response");
      if (!controller.signal.aborted) {
        if (!refreshTools) { clearCredentials(); setMethod(selected); }
        if (saved && !reconnecting) {
          setSaved({ ...saved, endpoint: refreshTools ? saved.endpoint : endpoint, authMethod: refreshTools ? saved.authMethod : oauthMethod ? "oauth" : selected, generation: body.connection.generation });
          if (!refreshTools) {
            setReplaceCredentials(false);
            if (oauthMethod) setSavedOAuth({ registrationMethod: oauthMethod, grant: oauthValues.grant, clientAuth: oauthValues.clientAuth });
          }
          setToolsRevision(value => value + 1);
        }
        else onConnected();
      }
    } catch { if (!controller.signal.aborted) setError("Could not connect. Check the URL and credentials, then retry."); }
    finally { if (!controller.signal.aborted) setBusy(false); }
  }

  async function openConflict() {
    if (!conflict || !onOpenConnection || busy || readOnly) return;
    const controller = new AbortController(); pending.current = controller;
    setBusy(true); setError("");
    try {
      const response = await fetchImpl(conflictUrl(tenantKey, conflict), { credentials: "same-origin", headers: { accept: "application/json" }, signal: controller.signal });
      if (controller.signal.aborted) return;
      if (response.status === 401) { onSessionExpired(); return; }
      if (!response.ok) throw new Error("Connection unavailable");
      const current = parseConflictConnection(await response.json(), tenantKey, conflict);
      if (!controller.signal.aborted) { clearCredentials(); onOpenConnection(current); }
    } catch { if (!controller.signal.aborted) setError("Could not load this connection. Retry, or close this dialog and load current integrations."); }
    finally { if (!controller.signal.aborted) setBusy(false); }
  }

  async function disconnect() {
    if (!saved || readOnly || busy) return;
    const controller = new AbortController(); pending.current = controller;
    setBusy(true); setError("");
    try {
      const response = await fetchImpl(connectionUrl, { method: "DELETE", credentials: "same-origin", signal: controller.signal,
        headers: { "content-type": "application/json", "x-csrf-token": csrfToken }, body: JSON.stringify({ generation: saved.generation }) });
      if (controller.signal.aborted) return;
      if (response.status === 401) { onSessionExpired(); return; }
      if (!response.ok) throw new Error("Disconnect failed");
      onConnected();
    } catch { if (!controller.signal.aborted) setError("Could not disconnect. Reload the connection and retry."); }
    finally { if (!controller.signal.aborted) setBusy(false); }
  }

  const form = <form className="mcp-dialog-form" noValidate onSubmit={event => { event.preventDefault(); void connect(); }}>
      <div className="mcp-dialog-scroll">
        {recoveryNotice && <p className="mcp-hint mb-4" role="status">{recoveryNotice}</p>}
        <fieldset disabled={busy || readOnly} className="m-0 min-w-0 border-0 p-0">
          <section className="mcp-form-section">
            {directoryEntry ? <>
              <div className="mcp-field"><span className="mcp-hint">MCP server URL</span><p className="break-all">{directoryEntry.endpoint}</p></div>
              {directoryEntry.setup_notes && <p className="mcp-hint whitespace-pre-wrap break-words">{directoryEntry.setup_notes}</p>}
              {(directoryEntry.setup_url || directoryEntry.documentation_url) && <div className="flex flex-wrap gap-4 text-sm">
                {directoryEntry.setup_url && <a className="underline" href={directoryEntry.setup_url} target="_blank" rel="noopener noreferrer">Setup</a>}
                {directoryEntry.documentation_url && <a className="underline" href={directoryEntry.documentation_url} target="_blank" rel="noopener noreferrer">Documentation</a>}
              </div>}
            </> : <TextField label="MCP server URL" type="url" disabled={reconnecting} value={endpoint} onChange={event => changeUrl(event.target.value)} placeholder="https://mcp.example.com/mcp" />}
            <div className="mcp-field-note">
              {discovery.status !== "idle" && <p className="mcp-hint" role="status">{discovery.status === "waiting" ? "Waiting to check URL…" : discovery.status === "checking" ? "Checking MCP server and OAuth settings…" : discovery.status === "failed" || discovery.data?.outcome === "unknown" ? listedOAuth ? "Could not discover OAuth settings. Check the authorization server URL, or retry." : "Could not discover settings. Choose authentication manually, or retry." : discovery.data?.outcome === "partial" ? "Some OAuth settings could not be discovered. Check the authorization server or retry." : discovery.data?.outcome === "unsupported_oauth" ? "This server does not support the OAuth security requirements needed to connect." : discovery.data?.outcome === "issuer_required" ? "Choose an authorization server to continue discovery." : discovery.data?.outcome === "anonymous" ? "Server accepts connections without authentication." : "OAuth settings discovered."}</p>}
              {(discovery.status === "failed" || discovery.data?.outcome === "unknown" || discovery.data?.outcome === "partial") && <Button type="button" onClick={discovery.retry}>Retry discovery</Button>}
            </div>
            {discovery.data && discovery.data.issuers.length > 1 && <SelectField label="Authorization server" value={issuer ?? ""} onChange={changeIssuer}><option value="" disabled>Select authorization server</option>{discovery.data.issuers.map(value => <option key={value} value={value}>{value}</option>)}</SelectField>}
            {listedOAuth && (manualIssuer || discovery.status === "failed" || ["unknown", "partial"].includes(discovery.data?.outcome ?? "")) && <TextField label="Authorization server URL" type="url" maxLength={2048} value={issuer ?? ""} onChange={event => { setManualIssuer(true); changeIssuer(event.target.value); }} placeholder="https://auth.example.com" />}
          </section>
          <section className="mcp-form-section"><h3>Authentication</h3>
            {directoryEntry ? <p className="mcp-hint">{apiKeyHeader ? "API key" : selected === "bearer" ? "Bearer token" : selected === "basic" ? "HTTP Basic" : selected === "none" ? "No authentication" : selected === "own_client" ? "OAuth · Registered client" : "OAuth"}</p> : <SelectField label="Authentication Type" value={selected} onChange={changeMethod}>
              <option value="" disabled>Select authentication type</option>
              <option value="cimd">OAuth - CIMD</option><option value="dcr">OAuth - DCR</option><option value="own_client">OAuth - Own client</option>
              <option value="bearer">Bearer token</option><option value="headers">Custom headers</option><option value="basic">HTTP Basic</option><option value="none">No authentication</option>
            </SelectField>}
            {saved && !reconnecting && selected !== "none" && <label className="mcp-hint"><input type="checkbox" checked={replaceCredentials} disabled={!directoryEntry && (endpoint !== saved.endpoint || selected !== savedMethod)} onChange={event => replaceSavedCredentials(event.target.checked)} /> Replace credentials</label>}
            {saved && !replaceCredentials && selected !== "none" && <p className="mcp-hint">Credentials saved. Values are never displayed.</p>}
            {replaceCredentials && reuseRegistration && <p className="mcp-hint">Sign in again using the saved client registration.</p>}
            {replaceCredentials && oauthMethod && !reuseRegistration && <OAuthFields method={oauthMethod} values={oauthValues} discovery={discovery.data}
              listed={listedOAuth} clientAuthConfirmed={clientAuthConfirmed}
              issuer={issuer ?? (typeof discovery.data?.oauth?.issuer === "string" ? discovery.data.oauth.issuer : "")}
              onIssuerChange={changeIssuer} onChange={patch => setOAuthEdits(current => ({ ...current, ...patch }))} />}
            {replaceCredentials && selected === "bearer" && <TextField label="Bearer token" secret value={token} onChange={event => setToken(event.target.value)} />}
            {replaceCredentials && selected === "basic" && <><TextField label="Username" value={username} onChange={event => setUsername(event.target.value)} autoComplete="off" /><TextField label="Password" secret value={password} onChange={event => setPassword(event.target.value)} /></>}
            {replaceCredentials && selected === "headers" && (apiKeyHeader ? <TextField label={apiKeyHeader} secret value={token} onChange={event => setToken(event.target.value)} /> : <Pairs label="Request headers" singular="Header" pairs={headers} onChange={setHeaders} secret />)}
            {!directoryEntry && replaceCredentials && (selected === "bearer" || selected === "basic") && <Disclosure title="Additional MCP request headers"><Pairs label="Request headers" singular="Header" pairs={headers} onChange={setHeaders} secret /></Disclosure>}
          </section>
        </fieldset>
        {error && <p className="mcp-error" role="alert">{error}</p>}
        {conflict && <div role="status" className="mcp-field-note"><p className="mcp-hint">{conflict.kind === "reconnect" ? "This server was disconnected. Review its saved settings to reconnect it." : "This server is already connected. Open its current settings to manage it."}</p><Button type="button" disabled={busy} onClick={() => void openConflict()}>{conflict.kind === "reconnect" ? "Review reconnect" : "Manage existing connection"}</Button></div>}
        {busy && <p role="status" className="mcp-hint"><LoaderCircle className="mcp-spinner inline" size={16} aria-hidden /> Checking authentication and discovering tools…</p>}
      </div>
      {saved && !reconnecting ? !readOnly && <div className="mcp-auth-actions px-6 pb-6"><Button type="submit" disabled={busy || !selected || !validMcpUrl(endpoint)}>{busy ? "Checking…" : replaceCredentials ? "Save changes" : "Test connection"}</Button></div> : <footer className="mcp-dialog-footer"><Button type="button" disabled={busy} onClick={onClose}>Cancel</Button>{!readOnly && <Button type="submit" className="mcp-primary" disabled={busy || !selected || !validMcpUrl(endpoint)}>{busy ? "Connecting…" : reconnecting ? "Reconnect" : "Connect"}<ArrowRight size={15} aria-hidden /></Button>}</footer>}
    </form>;
  return <div className="mcp-services-preview"><SetupDialog title={reconnecting ? `Reconnect ${saved?.serverName}` : saved?.serverName ?? (directoryEntry ? `Connect ${directoryEntry.name}` : "Connect other MCP")} onClose={onClose} busy={busy} anchorTop={!!saved && !reconnecting}>
    {saved && !reconnecting ? <>
      <Tabs className="mcp-manage-tabs" value={tab} onValueChange={setTab}>
        <TabsList className="mcp-manage-tab-list" variant="line" aria-label="Connection settings"><TabsTrigger value="authentication">Authentication</TabsTrigger><TabsTrigger value="tools">Tools</TabsTrigger></TabsList>
        <TabsContent value="authentication" className="mcp-manage-auth">{form}</TabsContent>
        <TabsContent value="tools" className="mcp-tools-panel">
          <div className="mcp-tools-heading"><h3>Available tools ({tools.length})</h3>{!readOnly && <Button aria-label="Refresh tools" disabled={busy} onClick={() => void connect(true)}><RefreshCw size={16} aria-hidden className={busy ? "mcp-spinner" : undefined} />Refresh tools</Button>}</div>
          <div className="mcp-search"><input type="search" aria-label="Search tools" placeholder="Search tools…" value={search} onChange={event => setSearch(event.target.value)} /></div>
          {toolsStatus === "loading" ? <p role="status">Loading tools…</p> : toolsStatus === "failed" ? <p role="alert">Could not load tools. <Button onClick={() => setToolsRevision(value => value + 1)}>Retry tools</Button></p> : <ul className="mcp-tool-list" aria-label="Available tools">{tools.filter(tool => tool.toLowerCase().includes(search.toLowerCase())).map(tool => <li key={tool}><code>{tool}</code></li>)}{tools.length === 0 && <li>No tools available.</li>}</ul>}
          {error && <p role="alert" className="mcp-error">{error}</p>}
        </TabsContent>
      </Tabs>
      <footer className="mcp-dialog-footer mcp-manage-footer">{!readOnly && <Button className="mcp-disconnect" variant="ghost" disabled={busy} onClick={() => void disconnect()}>Disconnect</Button>}<Button disabled={busy} onClick={onClose}>Close</Button></footer>
    </> : form}
  </SetupDialog></div>;
}

function parseHandoff(value: unknown): OAuthHandoff {
  if (!value || typeof value !== "object" || !("authorization_url" in value) || !("attempt_id" in value) || !("connection_id" in value) ||
    typeof value.authorization_url !== "string" || value.authorization_url.length > 32768 ||
    typeof value.attempt_id !== "string" || !/^[a-zA-Z0-9_-]{1,128}$/.test(value.attempt_id) ||
    typeof value.connection_id !== "string" || !/^[a-zA-Z0-9_-]{1,128}$/.test(value.connection_id)) throw new Error("Invalid OAuth handoff");
  const url = new URL(value.authorization_url);
  if (url.protocol !== "https:" || !url.hostname || url.username || url.password || url.hash) throw new Error("Invalid authorization URL");
  return { authorizationUrl: value.authorization_url, attemptId: value.attempt_id, connectionId: value.connection_id };
}

function parseSavedOAuth(value: unknown): SavedOAuth | null {
  if (!value || typeof value !== "object" || !("registration_method" in value) || !("grant_type" in value) || !("auth_method" in value) ||
    !["cimd", "dcr", "own_client"].includes(String(value.registration_method)) ||
    !["authorization_code", "client_credentials"].includes(String(value.grant_type)) ||
    !["none", "client_secret_basic", "client_secret_post", "private_key_jwt"].includes(String(value.auth_method))) return null;
  return { registrationMethod: value.registration_method as OAuthMethod, grant: value.grant_type as OAuthGrant, clientAuth: value.auth_method as ClientAuthentication };
}
