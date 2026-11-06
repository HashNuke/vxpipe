import { useEffect, useRef, useState } from "react";
import { ArrowRight, LoaderCircle, RefreshCw } from "lucide-react";
import { Button } from "../Button";
import { SetupDialog } from "../SetupDialog";
import { Disclosure, Pairs, SelectField, TextField } from "../mcpStories/FormControls";
import { useMcpDiscovery } from "./useMcpDiscovery";
import { validMcpUrl } from "./mcpDiscoveryApi";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../components/ui/tabs";
import type { McpConnection } from "./inventoryApi";
import type { IntegrationFetch } from "./useInventory";
import "../mcpStories/mcp-services-story.css";

type Method = "" | "none" | "bearer" | "headers" | "basic";
type Header = { id: number; name: string; value: string };
export function CustomMcpDialog({ tenantKey, csrfToken, fetchImpl, onSessionExpired, onClose, onConnected, connection }: {
  connection?: McpConnection; tenantKey: string; csrfToken: string; fetchImpl: IntegrationFetch; onSessionExpired: () => void;
  onClose: () => void; onConnected: () => void;
}) {
  const [endpoint, setEndpoint] = useState(connection?.endpoint ?? "");
  const [revision, setRevision] = useState(0);
  const [method, setMethod] = useState<Method>((connection?.authMethod ?? "") as Method);
  const [issuer, setIssuer] = useState<string>();
  const [token, setToken] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [headers, setHeaders] = useState<Header[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(connection);
  const [replaceCredentials, setReplaceCredentials] = useState(!connection);
  const [tools, setTools] = useState<string[]>([]);
  const [toolsStatus, setToolsStatus] = useState("loading");
  const [toolsRevision, setToolsRevision] = useState(0);
  const [tab, setTab] = useState("authentication");
  const [search, setSearch] = useState("");
  const readOnly = connection?.canEdit === false;
  const connectionUrl = `/api/tenants/${encodeURIComponent(tenantKey)}/mcp-connections${connection ? `/${encodeURIComponent(connection.id)}` : ""}`;
  useEffect(() => {
    if (!connection) return;
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
        if (!controller.signal.aborted) { setTools(body.connection.tools.map((tool: { name: string }) => tool.name)); setToolsStatus("ready"); }
      }).catch(() => { if (!controller.signal.aborted) setToolsStatus("failed"); });
    return () => controller.abort();
  }, [connection, connectionUrl, fetchImpl, onSessionExpired, toolsRevision]);
  const pending = useRef<AbortController | null>(null);
  useEffect(() => () => pending.current?.abort(), []);
  const discovery = useMcpDiscovery({ tenantKey, csrfToken, endpoint, revision: String(revision), issuer,
    active: !busy && !readOnly && (!saved || endpoint !== saved.endpoint), fetchImpl, onSessionExpired });
  const selected = method || (discovery.data?.suggestedMethod === "none" ? "none" : "");

  function clearCredentials() { setToken(""); setUsername(""); setPassword(""); setHeaders([]); }
  function changeUrl(value: string) {
    setReplaceCredentials(true); setEndpoint(value); setRevision(value => value + 1); setIssuer(undefined); setMethod(""); clearCredentials(); setError("");
  }
  function changeMethod(value: string) {
    if (value === selected) return;
    setReplaceCredentials(true); setMethod(value as Method); clearCredentials(); setError("");
    if (value === "headers") setHeaders([{ id: 1, name: "X-API-Key", value: "" }]);
  }
  async function connect(refreshTools = false) {
    if (readOnly || busy || (!refreshTools && (!selected || !validMcpUrl(endpoint)))) return;
    if (!refreshTools && replaceCredentials && ((selected === "bearer" && !token) || (selected === "basic" && (!username || !password)) ||
      (selected === "headers" && !headers.length) || headers.some(header => !header.name || !header.value))) {
      setError("Complete the credentials for the selected authentication type."); return;
    }
    const extra = headers.length ? { headers: headers.map(({ name, value }) => ({ name, value })) } : {};
    const credentials = selected === "none" ? {} : selected === "bearer" ? { token, ...extra } : selected === "basic" ? { username, password, ...extra } : extra;
    const controller = new AbortController(); pending.current = controller;
    setBusy(true); setError("");
    try {
      const response = await fetchImpl(connectionUrl, {
        method: saved ? "PATCH" : "POST", credentials: "same-origin", signal: controller.signal,
        headers: { accept: "application/json", "content-type": "application/json", "x-csrf-token": csrfToken },
        body: JSON.stringify(refreshTools && saved ? { generation: saved.generation, refresh_tools: true } : {
          endpoint, auth_method: selected, ...(replaceCredentials ? { credentials } : {}), ...(saved ? { generation: saved.generation } : {}),
        }),
      });
      if (controller.signal.aborted) return;
      if (response.status === 401) { onSessionExpired(); return; }
      if (!response.ok) { setError(response.status === 409 && saved ? "This connection changed since you opened it. Close and reopen to load the latest settings." : response.status === 409 ? "This server is already connected. Close this dialog to manage its connection." : "Could not connect. Check the URL and credentials, then retry."); return; }
      const body = await response.json();
      if (typeof body?.connection?.id !== "string" || typeof body?.connection?.generation !== "number") throw new Error("Invalid connection response");
      if (!controller.signal.aborted) {
        if (!refreshTools) { clearCredentials(); setMethod(selected); }
        if (saved) { setSaved({ ...saved, endpoint: refreshTools ? saved.endpoint : endpoint, authMethod: refreshTools ? saved.authMethod : selected, generation: body.connection.generation }); if (!refreshTools) setReplaceCredentials(false); setToolsRevision(value => value + 1); }
        else onConnected();
      }
    } catch { if (!controller.signal.aborted) setError("Could not connect. Check the URL and credentials, then retry."); }
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
        <fieldset disabled={busy || readOnly} className="m-0 min-w-0 border-0 p-0">
          <section className="mcp-form-section">
            <TextField label="MCP server URL" type="url" value={endpoint} onChange={event => changeUrl(event.target.value)} placeholder="https://mcp.example.com/mcp" />
            <div className="mcp-field-note">
              {discovery.status !== "idle" && <p className="mcp-hint" role="status">{discovery.status === "waiting" ? "Waiting to check URL…" : discovery.status === "checking" ? "Checking MCP server and OAuth settings…" : discovery.status === "failed" || discovery.data?.outcome === "unknown" ? "Could not discover settings. Choose authentication manually, or retry." : discovery.data?.outcome === "unsupported_oauth" ? "This server does not support the OAuth security requirements needed to connect." : discovery.data?.outcome === "issuer_required" ? "Choose an authorization server to continue discovery." : discovery.data?.outcome === "anonymous" ? "Server accepts connections without authentication." : "OAuth settings discovered. OAuth connection support is not available yet."}</p>}
              {(discovery.status === "failed" || discovery.data?.outcome === "unknown" || discovery.data?.outcome === "partial") && <Button type="button" onClick={discovery.retry}>Retry discovery</Button>}
            </div>
            {discovery.data && discovery.data.issuers.length > 1 && <SelectField label="Authorization server" value={issuer ?? ""} onChange={setIssuer}><option value="" disabled>Select authorization server</option>{discovery.data.issuers.map(value => <option key={value} value={value}>{value}</option>)}</SelectField>}
          </section>
          <section className="mcp-form-section"><h3>Authentication</h3>
            <SelectField label="Authentication Type" value={selected} onChange={changeMethod}>
              <option value="" disabled>Select authentication type</option>
              <option value="bearer">Bearer token</option><option value="headers">Custom headers</option><option value="basic">HTTP Basic</option><option value="none">No authentication</option>
            </SelectField>
            {saved && selected !== "none" && <label className="mcp-hint"><input type="checkbox" checked={replaceCredentials} disabled={endpoint !== saved.endpoint || selected !== saved.authMethod} onChange={event => { setReplaceCredentials(event.target.checked); clearCredentials(); }} /> Replace credentials</label>}
            {saved && !replaceCredentials && selected !== "none" && <p className="mcp-hint">Credentials saved. Values are never displayed.</p>}
            {replaceCredentials && selected === "bearer" && <TextField label="Bearer token" secret value={token} onChange={event => setToken(event.target.value)} />}
            {replaceCredentials && selected === "basic" && <><TextField label="Username" value={username} onChange={event => setUsername(event.target.value)} autoComplete="off" /><TextField label="Password" secret value={password} onChange={event => setPassword(event.target.value)} /></>}
            {replaceCredentials && selected === "headers" && <Pairs label="Request headers" singular="Header" pairs={headers} onChange={setHeaders} secret />}
            {replaceCredentials && (selected === "bearer" || selected === "basic") && <Disclosure title="Additional MCP request headers"><Pairs label="Request headers" singular="Header" pairs={headers} onChange={setHeaders} secret /></Disclosure>}
          </section>
        </fieldset>
        {error && <p className="mcp-error" role="alert">{error}</p>}
        {busy && <p role="status" className="mcp-hint"><LoaderCircle className="mcp-spinner inline" size={16} aria-hidden /> Checking authentication and discovering tools…</p>}
      </div>
      {saved ? !readOnly && <div className="mcp-auth-actions px-6 pb-6"><Button type="submit" disabled={busy || !selected || !validMcpUrl(endpoint)}>{busy ? "Checking…" : replaceCredentials ? "Save changes" : "Test connection"}</Button></div> : <footer className="mcp-dialog-footer"><Button type="button" disabled={busy} onClick={onClose}>Cancel</Button><Button type="submit" className="mcp-primary" disabled={busy || !selected || !validMcpUrl(endpoint)}>{busy ? "Connecting…" : "Connect"}<ArrowRight size={15} aria-hidden /></Button></footer>}
    </form>;
  return <SetupDialog title={saved?.serverName ?? "Connect other MCP"} onClose={onClose} busy={busy}>
    {saved ? <>
      <Tabs className="mcp-manage-tabs" value={tab} onValueChange={setTab}>
        <TabsList className="mcp-manage-tab-list" variant="line" aria-label="Connection settings"><TabsTrigger value="authentication">Authentication</TabsTrigger><TabsTrigger value="tools">Tools</TabsTrigger></TabsList>
        <TabsContent value="authentication">{form}</TabsContent>
        <TabsContent value="tools" className="mcp-tools-panel">
          <div className="mcp-tools-heading"><h3>Available tools ({tools.length})</h3>{!readOnly && <Button aria-label="Refresh tools" disabled={busy} onClick={() => void connect(true)}><RefreshCw size={16} aria-hidden className={busy ? "mcp-spinner" : undefined} />Refresh tools</Button>}</div>
          <div className="mcp-search"><input type="search" aria-label="Search tools" placeholder="Search tools…" value={search} onChange={event => setSearch(event.target.value)} /></div>
          {toolsStatus === "loading" ? <p role="status">Loading tools…</p> : toolsStatus === "failed" ? <p role="alert">Could not load tools. <Button onClick={() => setToolsRevision(value => value + 1)}>Retry tools</Button></p> : <ul className="mcp-tool-list" aria-label="Available tools">{tools.filter(tool => tool.toLowerCase().includes(search.toLowerCase())).map(tool => <li key={tool}><code>{tool}</code></li>)}{tools.length === 0 && <li>No tools available.</li>}</ul>}
          {error && <p role="alert" className="mcp-error">{error}</p>}
        </TabsContent>
      </Tabs>
      <footer className="mcp-dialog-footer mcp-manage-footer">{!readOnly && <Button className="mcp-disconnect" variant="ghost" disabled={busy} onClick={() => void disconnect()}>Disconnect</Button>}<Button disabled={busy} onClick={onClose}>Close</Button></footer>
    </> : form}
  </SetupDialog>;
}
