import { LoaderCircle, Plus, RefreshCw, Search } from "lucide-react";
import { Fragment, useId, type ReactNode } from "react";
import { Button } from "../Button";
import { ServiceLogo } from "../ServiceLogo";
import { capabilityLabels, setupProviders, type SetupConnection, type SetupProviderId } from "../setupCatalog";
import { customPreset, type Connection, type Preset } from "./fixtures";
import { RemoteDirectoryResults } from "./RemoteDirectoryResults";
import { shouldInterceptNavigation } from "../shouldInterceptNavigation";
import { DirectoryAction } from "./DirectoryAction";
import { DirectorySkeleton } from "./DirectorySkeleton";
import { type RemoteDirectoryFixture, type ConnectionLoadState, type DirectoryLoadState } from "./remoteDirectory";
import type { DirectoryCategory } from "./integrationCategoryRoute";
export type { DirectoryCategory } from "./integrationCategoryRoute";

const localCategories = [
  { id: "ai", label: "AI models", count: setupProviders.filter(provider => !provider.capabilities.includes("telephony")).length },
  { id: "telephony", label: "Telephony", count: setupProviders.filter(provider => provider.capabilities.includes("telephony")).length },
];

export function ServiceDirectory({ category, onCategory, categoryHref, connectedCount, renderConnected, readOnly = false, platform = false, canManagePlatform = false,
  search, onSearch, cursor, onCursor, pageSize, previewPageState,
  catalog, directoryState, connectionState, providerConnections, mcpConnections, onRetryDirectory, onRetryConnections, onSelect, onProvider,
}: {
  search: string; onSearch: (search: string) => void; cursor: string | null; onCursor: (cursor: string | null) => void;
  pageSize: number; previewPageState: "ready" | "loading" | "error";
  category: DirectoryCategory; onCategory: (category: DirectoryCategory) => void; categoryHref: (category: DirectoryCategory) => string;
  connectedCount: number; renderConnected: (query: string) => ReactNode; readOnly?: boolean; platform?: boolean; canManagePlatform?: boolean;
  catalog: RemoteDirectoryFixture; directoryState: DirectoryLoadState; connectionState: ConnectionLoadState;
  providerConnections: SetupConnection[]; mcpConnections: Connection[];
  onRetryDirectory: () => void; onRetryConnections: () => void;
  onSelect: (preset: Preset) => void; onProvider: (id: SetupProviderId) => void;
}) {
  const hasCatalog = ["ready", "stale"].includes(directoryState);
  const fallback = directoryState === "unavailable";
  const remoteCategories = hasCatalog && !platform ? [...catalog.categories].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id)).map(item => ({
    id: item.id, label: item.name, count: item.integration_count,
  })) : [];
  const visibleCategories = [{ id: "connected", label: "Connected integrations", count: connectionState === "ready" ? connectedCount : undefined }, ...localCategories, ...remoteCategories];
  const categoryId = useId();
  const query = search.trim().toLowerCase();
  const matches = (text: string) => text.toLowerCase().includes(query);
  const providers = setupProviders.filter(provider => (!["ai", "telephony"].includes(category) || provider.capabilities.includes("telephony") === (category === "telephony")) && matches(`${provider.name} ${provider.capabilities.map(capability => capabilityLabels[capability]).join(" ")}`));
  const label = visibleCategories.find(item => item.id === category)?.label ?? "Integrations";
  const remoteCategory = !["connected", "ai", "telephony"].includes(category);
  const waitingForCatalog = remoteCategory && !hasCatalog && !fallback;
  const status = (connected?: { status: string }) => !connected ? undefined : connected.status === "connected" ? "connected" as const : "attention" as const;
  return <>
    <div className="mcp-page-heading service-directory-heading">
      <h1>{platform ? "Platform Integrations" : "Integrations"}</h1>
      <div className="mcp-search"><Search size={17} aria-hidden /><input aria-label="Search integrations" type="search" placeholder="Search all integrations…" value={search} maxLength={200} onChange={event => onSearch(event.target.value)} /></div>
      {!platform && !readOnly && <Button className="mcp-primary service-directory-custom-action" onClick={event => { event.currentTarget.focus(); onSelect(customPreset); }}><Plus size={16} aria-hidden />Connect other MCP</Button>}
    </div>
    <div className="service-directory-layout">
      <aside className="service-directory-sidebar" aria-label="Integration categories and status">
      <nav className="service-directory-categories" aria-label="Integration categories">
        {visibleCategories.map((item, index) => <Fragment key={item.id}>
          {(index === 1 || index === 3) && <hr className="service-directory-category-separator" />}
          <a href={categoryHref(item.id)} aria-current={category === item.id ? "page" : undefined} onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); onCategory(item.id); }}><span>{item.label}</span><span>{item.count}</span></a>
        </Fragment>)}
        {directoryState === "loading" && !platform && <div className="directory-category-skeleton animate-pulse motion-reduce:animate-none" aria-hidden="true">
          <hr className="service-directory-category-separator" />
          {[0, 1, 2].map(row => <div className="directory-skeleton-shape" key={row} />)}
        </div>}
      </nav>
        <div className="service-directory-mobile-category"><label htmlFor={categoryId}>Category</label>
          <select id={categoryId} value={category} onChange={event => onCategory(event.target.value)}>
            <option value="connected">Connected integrations{connectionState === "ready" ? ` (${connectedCount})` : ""}</option>
            <optgroup label="AI and telephony">{localCategories.map(item => <option key={item.id} value={item.id}>{item.label} ({item.count})</option>)}</optgroup>
            {remoteCategories.length > 0 && <optgroup label="MCP integrations">{remoteCategories.map(item => <option key={item.id} value={item.id}>{item.label} ({item.count})</option>)}</optgroup>}
            {remoteCategory && !visibleCategories.some(item => item.id === category) && <option value={category}>{category === "search" ? "Search results" : "MCP integrations"}</option>}
          </select>
        </div>
        {fallback && <div className="directory-sidebar-notice" role="alert">
          <div><strong>Integration directory unavailable</strong><Button variant="ghost" aria-label="Retry directory" title="Retry directory" onClick={onRetryDirectory}><RefreshCw size={15} aria-hidden /></Button></div>
          <p>Showing built-in AI and telephony services</p>
        </div>}
      </aside>
      <div className="service-directory-results" aria-busy={waitingForCatalog || undefined}>
        {directoryState === "stale" && <div className="directory-message" role="status">
            <div><strong>Showing saved directory listings</strong><p>Refresh the directory to browse more results or connect a new MCP. Existing connections are available to edit.</p></div>
            <Button onClick={onRetryDirectory}>Retry directory</Button>
        </div>}
        {category !== "connected" && connectionState !== "ready" ? <div className="directory-message" role={connectionState === "unavailable" ? "alert" : "status"}>
          {connectionState === "loading" ? <><LoaderCircle size={18} className="mcp-spinner" aria-hidden /><span>Checking connected integrations…</span></> : <><div><strong>Connection status unavailable</strong><p>Retry to see which integrations are connected.</p></div><Button onClick={onRetryConnections}>Retry connections</Button></>}
        </div> : null}
        {category === "connected" ? renderConnected(query) : waitingForCatalog ? <DirectorySkeleton /> : hasCatalog ? <RemoteDirectoryResults key={`${category}:${search}`} catalog={catalog} category={category} search={search} cursor={cursor} onCursor={onCursor} onClearSearch={() => onSearch("")} pageSize={pageSize} previewPageState={previewPageState} directoryState={directoryState} connectionState={connectionState} connections={mcpConnections} providerConnections={providerConnections} platform={platform} canManagePlatform={canManagePlatform} onProvider={onProvider} readOnly={readOnly} onSelect={onSelect} /> : providers.length === 0 ? <div className="service-directory-empty" role="status">
          <h2>{fallback ? "No matching installed integrations" : "No matching integrations"}</h2>
          <p>{fallback && !platform ? "Retry the directory to search MCP listings, or connect a server by URL." : "Try a different search or category."}</p>{search && <Button onClick={() => onSearch("")}>Clear search</Button>}
        </div> : <section className="service-directory-group" aria-label={remoteCategory ? "Installed services" : label}><h2>{remoteCategory ? "Installed services" : label}</h2><div className="service-directory-list">
          {providers.map(provider => {
            const connected = providerConnections.find(item => item.provider === provider.id);
            return <article className="service-directory-row" aria-label={provider.name} key={provider.id}>
              <ServiceLogo provider={provider.id} name={provider.name} />
              <div className="service-directory-name"><h3>{provider.name}</h3><div className="setup-tags service-directory-capabilities">{provider.capabilities.map(capability => <span key={capability}>{capabilityLabels[capability]}</span>)}</div></div>
              <DirectoryAction name={provider.name} status={status(connected)} state={connectionState} readOnly={readOnly || (!platform && connected?.source === "platform" && !canManagePlatform)} onSelect={() => onProvider(provider.id)} />
            </article>;
          })}
        </div></section>}
      </div>
    </div>
  </>;
}
