import { LoaderCircle } from "lucide-react";
import { useState } from "react";
import { Button } from "../Button";
import { ServiceLogo } from "../ServiceLogo";
import { capabilityLabels, setupProviders, type SetupConnection, type SetupProviderId } from "../setupCatalog";
import { directoryRequest } from "./directoryRequest";
import { Pagination } from "../Pagination";
import { McpServiceIcon } from "./McpServiceIcon";
import { DirectoryAction } from "./DirectoryAction";
import { directoryPageFixture } from "./directoryPageFixture";
import { directoryPreset, matchingMcpConnection, type RemoteDirectoryFixture, type ConnectionLoadState, type DirectoryLoadState } from "./remoteDirectory";
import type { Connection, Preset } from "./fixtures";

export function RemoteDirectoryResults({ catalog, category, search, cursor, onCursor, onClearSearch, pageSize, previewPageState, directoryState, connectionState, connections, providerConnections, platform, canManagePlatform = false, onProvider, readOnly, onSelect }: {
  catalog: RemoteDirectoryFixture; category: string; search: string; cursor: string | null;
  onCursor: (cursor: string | null) => void; onClearSearch: () => void; pageSize: number;
  previewPageState: "ready" | "loading" | "error"; directoryState: DirectoryLoadState;
  connectionState: ConnectionLoadState; connections: Connection[]; providerConnections: SetupConnection[]; platform: boolean; canManagePlatform?: boolean; onProvider: (id: SetupProviderId) => void; readOnly: boolean; onSelect: (preset: Preset) => void;
}) {
  // In production this is a returned API page, not a browser-filtered full catalog.
  const page = directoryPageFixture(catalog, directoryRequest({ category: category === "search" ? null : category, query: search, cursor, limit: pageSize, scope: platform ? "platform" : "tenant" }));
  const [pageState, setPageState] = useState(page?.pagination.next_cursor ? previewPageState : "ready");
  const categoryLabel = category === "search" ? "Search results" : category === "ai" ? "AI models" : category === "telephony" ? "Telephony" : catalog.categories.find(item => item.id === category)?.name;
  const navigate = (next: string | null) => { setPageState("ready"); onCursor(next); };
  if (!page) return <div className="directory-message" role="alert"><div><strong>This page has expired</strong><p>Start from the first page to see the latest results.</p></div><Button onClick={() => navigate(null)}>Start from first page</Button></div>;
  if (!page.items.length) return <div className="service-directory-empty" role="status"><h2>{categoryLabel ? "No matching integrations" : "Category unavailable"}</h2><p>Try a different search or category.</p>{search && <Button onClick={onClearSearch}>Clear search</Button>}</div>;
  const paging = page.pagination;
  const busy = pageState === "loading";
  const available = pageState === "ready" && directoryState === "ready";
  return <section className="service-directory-group" aria-label={categoryLabel}>
    <h2>{categoryLabel}</h2>
    {pageState !== "ready" && <div className="directory-message" role={busy ? "status" : "alert"}>
      {busy ? <><LoaderCircle size={18} className="mcp-spinner" aria-hidden /><span>Loading next page…</span></> : <><div><strong>Could not load the next page</strong><p>Your current results are still available.</p></div><Button onClick={() => navigate(paging.next_cursor)}>Retry page</Button></>}
    </div>}
    <div className="service-directory-list" aria-busy={busy || undefined}>
      {page.items.map(entry => {
        if (entry.kind === "provider") {
          const provider = setupProviders.find(item => item.id === entry.connection.provider_id);
          if (!provider) return null;
          const saved = providerConnections.find(item => item.provider === provider.id);
          return <article className="service-directory-row" aria-label={provider.name} key={entry.id}>
            <ServiceLogo provider={provider.id} name={provider.name} />
            <div className="service-directory-name"><h3>{provider.name}</h3><div className="setup-tags service-directory-capabilities">{provider.capabilities.map(capability => <span key={capability}>{capabilityLabels[capability]}</span>)}</div></div>
            <DirectoryAction name={provider.name} status={saved ? saved.status === "connected" ? "connected" : "attention" : undefined} state={connectionState} readOnly={readOnly || (!platform && saved?.source === "platform" && !canManagePlatform)} onSelect={() => onProvider(provider.id)} />
          </article>;
        }
        const preset = directoryPreset(entry, page.directory_id);
        const saved = matchingMcpConnection(connections, preset);
        return <article className="service-directory-row" aria-label={preset.name} key={preset.id}>
          <McpServiceIcon preset={preset} />
          <div className="service-directory-name"><h3>{preset.name}{preset.preview && <span className="mcp-preview-label">Developer Preview</span>}</h3>{preset.description && <p>{preset.description}</p>}{preset.retired && <p>No longer available for new connections</p>}</div>
          <DirectoryAction name={preset.name} status={saved ? saved.status === "connected" ? "connected" : "attention" : undefined} state={connectionState} readOnly={readOnly} unavailable={preset.retired || directoryState === "stale"} onSelect={() => onSelect(preset)} />
        </article>;
      })}
    </div>
    <Pagination ariaLabel="Integration pages" pagination={{ label: `${paging.start_index}–${paging.end_index} of ${paging.total_items}`, hasPrevious: available && paging.previous_cursor !== null, hasNext: available && paging.next_cursor !== null }} onPrevious={() => navigate(paging.previous_cursor)} onNext={() => navigate(paging.next_cursor)} />
  </section>;
}
