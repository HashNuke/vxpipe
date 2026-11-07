import { Fragment, useEffect, useId, useState } from "react";
import { useLocation, useNavigate } from "react-router";
import { CheckCheck, CircleAlert, Plug, RefreshCw, Search } from "lucide-react";
import { Button } from "../Button";
import { ServiceLogo } from "../ServiceLogo";
import { capabilityLabels, type SetupProviderId } from "../setupCatalog";
import { shouldInterceptNavigation } from "../shouldInterceptNavigation";
import { integrationQuery, parseCategories, type IntegrationCategory, type IntegrationConnection } from "./inventoryApi";
import { CustomMcpDialog } from "./CustomMcpDialog";
import { useInventory, type IntegrationFetch } from "./useInventory";
import { useOAuthReturn, type RestoredMcpDialog } from "./useOAuthReturn";
import type { McpListing } from "./listedMcp";
import "../mcpStories/mcp-services-story.css";

const defaultFetch: IntegrationFetch = (input, init) => window.fetch(input, init);
const sessionExpired = () => window.location.assign("/auth/login");
const localCategories: { id: string; name: string; count?: number }[] = [{ id: "connected", name: "Connected integrations" }, { id: "ai", name: "AI models" }, { id: "telephony", name: "Telephony" }];

export function IntegrationsDirectory({ tenantKey, actorId, onAuthorizationRedirect, fetchImpl = defaultFetch, onSessionExpired = sessionExpired, onManage, onRemove, removingProvider, revision, csrfToken = "", canEdit = false, canManageMcps = false }: {
  actorId?: string; onAuthorizationRedirect?: (url: string) => void;
  csrfToken?: string; canEdit?: boolean; canManageMcps?: boolean; tenantKey: string | null; fetchImpl?: IntegrationFetch; onSessionExpired?: () => void;
  onManage: (provider: SetupProviderId, connection?: IntegrationConnection) => void;
  onRemove?: (provider: SetupProviderId, bindingName: string) => void; removingProvider?: SetupProviderId | null; revision?: unknown;
}) {
  const location = useLocation();
  const navigate = useNavigate();
  const categoryId = useId();
  const base = tenantKey === null ? "/platform/services" : `/t/${encodeURIComponent(tenantKey)}/services`;
  const prefix = tenantKey === null ? "/api/platform" : `/api/tenants/${encodeURIComponent(tenantKey)}`;
  const params = new URLSearchParams(location.search);
  const search = (params.get("q") ?? "").slice(0, 200);
  const pathCategory = location.pathname.startsWith(`${base}/`) ? location.pathname.slice(base.length + 1) : "connected";
  const category = search.trim() ? "search" : /^[a-z][a-z0-9-]{0,63}$/.test(pathCategory) ? pathCategory : "connected";
  const cursor = category === "connected" ? null : params.get("cursor");
  const [searchInput, setSearchInput] = useState(search);
  const [mcpDialog, setMcpDialog] = useState<(RestoredMcpDialog & { listing?: McpListing }) | null>(null);
  const [retry, setRetry] = useState(0);
  const [categories, setCategories] = useState<IntegrationCategory[]>([]);
  const [categoriesFailed, setCategoriesFailed] = useState(false);
  const query = integrationQuery(category, search, cursor);
  const context = `${prefix}:${category}:${search}`;
  const state = useInventory(`${prefix}/integrations?${query}`, context, tenantKey, fetchImpl, onSessionExpired, revision, retry, cursor);
  const data = state.data;
  const busy = state.status === "loading";
  const oauthReturn = useOAuthReturn({ actorId, tenantKey, ready: state.status === "ready", inventory: data, canManageMcps, onRestore: setMcpDialog, onAuthorizationRedirect });
  const categoriesList = [...localCategories, ...(tenantKey === null ? [] : categories)];
  const label = category === "search" ? "Search results" : categoriesList.find(item => item.id === category)?.name ?? "MCP integrations";

  useEffect(() => setSearchInput(search), [search]);
  useEffect(() => {
    if (searchInput === search) return;
    const timer = window.setTimeout(() => {
      const query = new URLSearchParams();
      if (searchInput.trim()) query.set("q", searchInput);
      navigate(`${base}/${searchInput.trim() ? "search" : "connected"}${query.size ? `?${query}` : ""}`, { replace: true });
    }, 350);
    return () => window.clearTimeout(timer);
  }, [searchInput, search, base, navigate]);
  useEffect(() => {
    if (tenantKey === null) return;
    const controller = new AbortController();
    fetchImpl(`${prefix}/integrations/categories`, { credentials: "same-origin", headers: { accept: "application/json" }, signal: controller.signal })
      .then(async response => {
        if (controller.signal.aborted) return;
        if (response.status === 401) { onSessionExpired(); return; }
        if (!response.ok) throw new Error("categories unavailable");
        const result = parseCategories(await response.json());
        if (!controller.signal.aborted) { setCategories(result); setCategoriesFailed(false); }
      }).catch(() => { if (!controller.signal.aborted) setCategoriesFailed(true); });
    return () => controller.abort();
  }, [prefix, tenantKey, fetchImpl, onSessionExpired, retry]);

  function selectCategory(value: string) { setSearchInput(""); navigate(`${base}/${value}`); }
  function selectCursor(value: string | null) {
    const next = new URLSearchParams(location.search);
    if (value) next.set("cursor", value); else next.delete("cursor");
    navigate(`${base}/${category}${next.size ? `?${next}` : ""}`);
  }

  function closeMcp() { setMcpDialog(null); setRetry(value => value + 1); }
  const showMcpDialog = !!mcpDialog && tenantKey !== null && mcpDialog.tenantKey === tenantKey && mcpDialog.actorId === actorId && (!!mcpDialog.connection || canManageMcps);

  return <>
    {showMcpDialog && mcpDialog && tenantKey !== null && <CustomMcpDialog key={`${tenantKey}:${mcpDialog.connection?.id ?? mcpDialog.listing?.reference.integration_id ?? "new"}`} tenantKey={tenantKey} csrfToken={csrfToken} fetchImpl={fetchImpl} onSessionExpired={onSessionExpired} onClose={closeMcp} onConnected={closeMcp} connection={mcpDialog.connection ? { ...mcpDialog.connection, canEdit: mcpDialog.connection.canEdit && canManageMcps } : undefined} listing={mcpDialog.listing} initialDraft={mcpDialog.initialDraft} returnTo={oauthReturn.returnTo} onAuthorize={oauthReturn.authorize} recoveryNotice={mcpDialog.initialDraft ? oauthReturn.notice ?? undefined : undefined} />}
    {oauthReturn.notice && !(showMcpDialog && mcpDialog?.initialDraft) && <p className="mb-4" role="status">{oauthReturn.notice}</p>}
    <nav aria-label="Integration breadcrumb" className="mb-6 text-sm text-[var(--admin-muted)]">Integrations <span aria-hidden="true"> / </span><span className="text-[var(--admin-ink)]">{label}</span></nav>
    <div className="mcp-page-heading service-directory-heading">
      <h1>{tenantKey === null ? "Platform Integrations" : "Integrations"}</h1>
      {tenantKey !== null && canManageMcps && csrfToken && data && <Button disabled={state.status !== "ready"} onClick={() => setMcpDialog({ tenantKey, actorId })}>Connect other MCP</Button>}
      <div className="mcp-search"><Search size={17} aria-hidden /><input aria-label="Search integrations" type="search" placeholder="Search all integrations…" maxLength={200} value={searchInput} onChange={event => setSearchInput(event.target.value)} /></div>
    </div>
    <div className="service-directory-layout">
      <aside className="service-directory-sidebar" aria-label="Integration categories and status">
        <nav className="service-directory-categories" aria-label="Integration categories">{categoriesList.map((item, index) => <Fragment key={item.id}>
          {(index === 1 || index === 3) && <hr className="service-directory-category-separator" />}
          <a href={`${base}/${item.id}`} aria-current={category === item.id ? "page" : undefined} onClick={event => { if (shouldInterceptNavigation(event)) { event.preventDefault(); selectCategory(item.id); } }}><span>{item.name}</span>{"count" in item && <span>{item.count}</span>}</a>
        </Fragment>)}</nav>
        <div className="service-directory-mobile-category"><label htmlFor={categoryId}>Category</label><select id={categoryId} value={category} onChange={event => selectCategory(event.target.value)}>
          {categoriesList.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}
          {!categoriesList.some(item => item.id === category) && <option value={category}>{label}</option>}
        </select></div>
        {(data?.status === "unavailable" || categoriesFailed) && <div className="directory-sidebar-notice" role="alert"><div><strong>Integration directory unavailable</strong><Button variant="ghost" aria-label="Retry directory" onClick={() => setRetry(value => value + 1)}><RefreshCw size={15} aria-hidden /></Button></div><p>Showing built-in AI and telephony services</p></div>}
      </aside>
      <div className="service-directory-results" aria-busy={busy}>
        {state.status === "error" && <div className="directory-message" role="alert"><div><strong>{data ? "This page could not be loaded" : "Connection status unavailable"}</strong><p>{data ? "Your current results are still shown." : "Retry to load integrations and their current connection status."}</p></div><Button onClick={() => setRetry(value => value + 1)}>{data ? "Retry page" : "Retry connections"}</Button></div>}
        {state.status === "expired" && <div className="directory-message" role="alert"><span>This directory page has expired.</span><Button onClick={() => selectCursor(null)}>Start from first page</Button></div>}
        {state.status === "invalid-page" && <div className="directory-message" role="alert"><span>This page link is no longer valid for these results.</span><Button onClick={() => selectCursor(null)}>Start from first page</Button></div>}
        {state.status === "missing" && <div className="directory-message" role="alert">This integration category is unavailable. Choose another category.</div>}
        {busy && !data && <p role="status">Loading integrations…</p>}
        {data && <section className="service-directory-group" aria-label={data.status === "unavailable" ? "Installed services" : label}>
          <h2>{data.status === "unavailable" ? "Installed services" : label}</h2>
          {data.items.length === 0 ? <div className="service-directory-empty" role="status"><h3>{category === "connected" ? "No connected integrations" : "No matching integrations"}</h3><p>{category === "connected" ? "Browse AI models or Telephony to connect an integration." : "Try a different search or category."}</p></div> : <div className="service-directory-list">{data.items.map(item => {
            const native = item.provider;
            return <article className="service-directory-row" aria-label={item.name} key={item.id}>
              {native ? <ServiceLogo provider={native} name={item.name} /> : <DirectoryLogo key={item.logoUrl ?? "none"} url={item.logoUrl} />}
              <div className="service-directory-name"><h3>{item.name}</h3>{native && item.capabilities.length > 0 ? <div className="setup-tags service-directory-capabilities">{item.capabilities.map(capability => <span key={capability}>{capabilityLabels[capability]}</span>)}</div> : <p>{item.summary}</p>}</div>
              <div className="directory-row-actions">{item.mcpConnections.map(connection => <Fragment key={connection.id}>
                <span className="setup-service-status" title={connection.status === "connected" ? "Connected" : "Reconnect required"}>{connection.status === "connected" ? <CheckCheck size={18} aria-hidden /> : <CircleAlert size={18} aria-hidden />}<span className="sr-only">{connection.status === "connected" ? "Connected" : "Reconnect required"}</span></span>
                <Button disabled={state.status !== "ready"} aria-label={`Manage ${connection.serverName}`} onClick={() => tenantKey && setMcpDialog({ tenantKey, actorId, connection: { ...connection, canEdit: connection.canEdit && canManageMcps } })}>Manage</Button>
              </Fragment>)}{item.connections.map(connection => <Fragment key={`${connection.provider}:${connection.name}`}>
                {connection.status === "connected" ? <span className="setup-service-status" title="Connected"><CheckCheck size={18} aria-hidden /><span className="sr-only">Connected</span></span> : <span className="mcp-status-warning directory-attention"><CircleAlert size={16} aria-hidden />Reconnect required</span>}
                <Button disabled={!canEdit || !(connection.canEdit || (tenantKey !== null && connection.source === "platform" && canEdit)) || !!removingProvider || state.status !== "ready"} aria-label={`Edit ${item.name}${item.connections.length > 1 ? ` (${connection.name})` : ""}`} onClick={() => item.provider && onManage(item.provider, connection)}>{item.connections.length > 1 ? `Edit ${connection.name}` : "Edit"}</Button>
              {onRemove && connection.canEdit && connection.credentialId && (tenantKey === null || connection.source === "tenant") && <Button variant="ghost" disabled={!!removingProvider || state.status !== "ready"} aria-label={`Remove ${item.name} (${connection.name}) credentials`} onClick={() => item.provider && onRemove(item.provider, connection.name)}>{removingProvider === item.provider ? "Removing…" : "Remove"}</Button>}
              </Fragment>)}{item.connections.length === 0 && item.mcpConnections.length === 0 && <>
                <Button disabled={!item.canConnect || state.status !== "ready" || (item.kind === "mcp" && (!canManageMcps || !csrfToken || !item.listing))} aria-label={`Connect ${item.name}`} onClick={() => {
                  if (item.provider) onManage(item.provider, undefined);
                  else if (tenantKey && item.listing && canManageMcps) setMcpDialog({ tenantKey, actorId, listing: item.listing });
                }}>Connect</Button>
              </>}</div>
            </article>;
          })}</div>}
        </section>}
        {data?.pagination && <nav className="mt-6 flex items-center justify-between gap-4" aria-label="Directory pages"><span className="text-sm text-[var(--admin-muted)]">{data.pagination.start}–{data.pagination.end} of {data.pagination.total}</span><div className="flex gap-2"><Button disabled={busy || !data.pagination.previous} onClick={() => selectCursor(data.pagination?.previous ?? null)}>Previous</Button><Button disabled={busy || !data.pagination.next} onClick={() => selectCursor(data.pagination?.next ?? null)}>Next</Button></div></nav>}
      </div>
    </div>
  </>;
}

function DirectoryLogo({ url }: { url?: string }) {
  const [failed, setFailed] = useState(false);
  return url && !failed
    ? <img src={url} alt="" className="size-10 object-contain" referrerPolicy="no-referrer" onError={() => setFailed(true)} />
    : <Plug aria-hidden className="size-10" />;
}
