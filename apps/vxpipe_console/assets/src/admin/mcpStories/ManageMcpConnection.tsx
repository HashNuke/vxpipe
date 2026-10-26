import { CircleAlert, Info, RefreshCw, Search, Unplug } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Button } from "../Button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "../components/ui/tabs";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "../components/ui/tooltip";
import { AuthenticationFields } from "./AuthenticationFields";
import { McpSetupInformation } from "./McpSetupInformation";
import { TextField } from "./FormControls";
import { authLabels, draftForConnection, type Connection, type Draft } from "./fixtures";

export function McpConnectionHeader({ connection }: { connection: Connection }) {
  const method = connection.auth === "custom"
    ? { oauth: "OAuth · Registered client", bearer: "Bearer token", basic: "Basic authentication", headers: "API key / headers" }[draftForConnection(connection).customAuth]
    : authLabels[connection.auth];
  return <div className="mcp-manage-identity">
    <span className="mcp-manage-title">{connection.name}</span>
    <div className="mcp-manage-account"><span>{connection.account ?? "No authentication"}</span>
      <TooltipProvider><Tooltip><TooltipTrigger asChild>
        <Button variant="ghost" className="mcp-auth-info" aria-label={`Authentication: ${method}`}><Info size={15} aria-hidden /></Button>
      </TooltipTrigger><TooltipContent className="setup-service-tooltip" side="bottom" sideOffset={6}>{method}</TooltipContent></Tooltip></TooltipProvider>
    </div>
  </div>;
}

export function ManageMcpConnection({ connection, draft, update, error, readOnly, onSubmit, onReconnect, onDisconnect, onClose }: {
  connection: Connection; draft: Draft; update: (patch: Partial<Draft>) => void; error: string | null; readOnly: boolean;
  onSubmit: () => void; onReconnect: () => void; onDisconnect: () => void; onClose: () => void;
}) {
  const [tab, setTab] = useState("authentication");
  const [search, setSearch] = useState("");
  const [refreshing, setRefreshing] = useState(false);
  const [changed, setChanged] = useState(false);
  const errorRef = useRef<HTMLDivElement>(null);
  const oauth = draft.auth !== "none" && (draft.auth !== "custom" || (draft.customAuth === "oauth" && draft.grant === "authorization_code"));
  const configurable = draft.preset.id === "custom" || draft.auth === "custom";
  const matching = connection.tools.filter(tool => tool.toLowerCase().includes(search.trim().toLowerCase()));
  useEffect(() => { if (error) errorRef.current?.focus(); }, [error]);
  useEffect(() => {
    if (!refreshing) return;
    const timer = window.setTimeout(() => setRefreshing(false), 800);
    return () => window.clearTimeout(timer);
  }, [refreshing]);
  const change = (patch: Partial<Draft>) => { setChanged(true); update(patch); };
  return <>
    <Tabs className="mcp-manage-tabs" value={tab} onValueChange={setTab}>
      <TabsList className="mcp-manage-tab-list" variant="line" aria-label="Connection settings">
        <TabsTrigger value="authentication">Authentication</TabsTrigger>
        <TabsTrigger value="tools">Tools</TabsTrigger>
      </TabsList>
      <TabsContent value="authentication" className="mcp-manage-auth mcp-dialog-scroll">
        {connection.status === "reconnect" && <div className="mcp-warning" role="status"><CircleAlert size={18} aria-hidden /><p>Authorization has expired or been revoked. Reconnect to restore access.</p></div>}
        <form onSubmit={event => { event.preventDefault(); onSubmit(); }} noValidate>
          <fieldset disabled={readOnly} className="mcp-auth-fields">
            {draft.preset.id === "custom" && <TextField label="MCP server URL" type="url" value={draft.endpoint} onChange={event => change({ endpoint: event.target.value })} />}
            {configurable ? <AuthenticationFields draft={draft} update={change} />
              : <><McpSetupInformation preset={draft.preset} /><p className="mcp-hint">{oauth ? "Reconnect to authorize this account again or choose another account." : "This connection does not require authentication."}</p></>}
          </fieldset>
          {error && <div className="mcp-error" role="alert" tabIndex={-1} ref={errorRef}><CircleAlert size={17} aria-hidden /><p>{error}</p></div>}
          {!readOnly && (oauth || configurable) && <div className="mcp-auth-actions">
            {oauth && !changed
              ? <Button className="mcp-primary" type="button" onClick={onReconnect}>Reconnect</Button>
              : <Button className="mcp-primary" type="submit" disabled={!changed}>Save changes</Button>}
          </div>}
        </form>
      </TabsContent>
      <TabsContent value="tools" className="mcp-tools-panel">
        <div className="mcp-tools-heading"><h3>Available tools ({connection.tools.length})</h3>
          {!readOnly && <Button className="mcp-refresh-tools" aria-label="Refresh tools" aria-busy={refreshing || undefined} title="Refresh tools" disabled={refreshing || connection.status === "reconnect"} onClick={() => setRefreshing(true)}><RefreshCw className={refreshing ? "animate-spin motion-reduce:animate-none" : undefined} size={16} aria-hidden /><span>Refresh tools</span></Button>}
        </div>
        <div className="mcp-search"><Search size={16} aria-hidden /><input type="search" aria-label="Search tools" placeholder="Search tools…" value={search} onChange={event => setSearch(event.target.value)} /></div>
        <ul className="mcp-tool-list" aria-label="Available tools" tabIndex={0}>
          {matching.map(tool => <li key={tool}><code>{tool}</code></li>)}
          {!matching.length && <li className="mcp-hint">{connection.tools.length ? "No tools match your search." : "No tools available."}</li>}
        </ul>
      </TabsContent>
    </Tabs>
    <footer className="mcp-dialog-footer mcp-manage-footer">
      {!readOnly && <Button className="mcp-disconnect" variant="ghost" onClick={onDisconnect}><Unplug size={15} aria-hidden />Disconnect</Button>}
      <Button onClick={onClose}>Close</Button>
    </footer>
  </>;
}
