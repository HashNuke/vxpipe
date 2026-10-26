import { useState } from "react";
import { ConnectedProviders } from "../mcpStories/ConnectedProviders";
import { ServiceConnectionsPreview } from "../mcpStories/ServiceConnectionsPreview";
import { StoryProviderDialog } from "../mcpStories/StoryProviderDialog";
import type { SetupConnection, SetupTenant } from "../setupCatalog";
export function NavigationServices({ tenant, platform = false, readOnly = false, canManagePlatform = false }: { tenant: SetupTenant; platform?: boolean; readOnly?: boolean; canManagePlatform?: boolean; canReadKeys?: boolean; onNavigate: (path: string) => void }) {
  const [overriding, setOverriding] = useState(false);
  const [connections, setConnections] = useState<SetupConnection[]>([
    { provider: "deepgram", status: "connected", source: platform ? "platform" : "tenant" },
    { provider: "google", status: "connected", source: "platform" },
  ]);
  return <div className="tenant-setup"><ServiceConnectionsPreview embedded={!platform} tenant={tenant} platform={platform} readOnly={readOnly} canManagePlatform={canManagePlatform}
    providerConnections={connections}
    renderInventory={({ query, onConnect }) => <ConnectedProviders query={query} connections={connections} platform={platform} readOnly={readOnly} canManagePlatform={canManagePlatform}
      platformConnections={platform ? [] : [{ provider: "google", status: "connected", source: "platform" }]}
      onManage={provider => { setOverriding(false); onConnect(provider); }} />}
    renderProviderDialog={({ providerId, editing, onClose, onConnected }) => <StoryProviderDialog
      state={{ provider: providerId, status: "idle", overriding }} connections={editing ? connections : []}
      scope={platform ? { kind: "platform" } : { kind: "tenant", tenantKey: tenant.key, tenantName: tenant.name }}
      onOverride={() => setOverriding(true)} onClose={() => { setOverriding(false); onClose(); }}
      onTest={async () => ({ status: "valid" })}
      onSubmit={draft => { setConnections(current => [...current.filter(item => item.provider !== draft.provider), { provider: draft.provider, status: "connected", source: platform ? "platform" : "tenant" }]); setOverriding(false); onConnected(); }} />}
  /></div>;
}
