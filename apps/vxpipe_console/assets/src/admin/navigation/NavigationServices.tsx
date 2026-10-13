import { useState } from "react";
import { TenantSetupPage } from "../TenantSetupPage";
import { ServiceSetupModal, type ServiceModalState } from "../ServiceSetupModal";
import type { SetupConnection, SetupTenant } from "../setupCatalog";
export function NavigationServices({ tenant, platform = false, readOnly = false, canReadKeys = true, onNavigate }: { tenant: SetupTenant; platform?: boolean; readOnly?: boolean; canReadKeys?: boolean; onNavigate: (path: string) => void }) {
  const [connections, setConnections] = useState<SetupConnection[]>([
    { provider: "deepgram", status: "connected", source: platform ? "platform" : "tenant" },
    { provider: "google", status: "connected", source: "platform" },
  ]);
  const [modal, setModal] = useState<ServiceModalState | null>(null);
  return <div className="tenant-setup">
    <div inert={modal ? true : undefined} aria-hidden={modal ? true : undefined}>
      <TenantSetupPage tenant={tenant} platform={platform} presentation="workspace" connections={connections} readOnly={readOnly}
        onConnect={provider => setModal({ provider, status: "idle" })} onBrowse={() => setModal({ provider: null, status: "idle" })}
        onRetry={() => undefined} onApiKeys={!platform && canReadKeys ? () => onNavigate(`/t/${tenant.key}/api-keys`) : undefined} />
    </div>
    {modal ? <ServiceSetupModal state={modal} connections={connections} scope={platform ? { kind: "platform" } : { kind: "tenant", tenantKey: tenant.key, tenantName: tenant.name }}
      onClose={() => setModal(null)} onSelect={provider => setModal({ provider, status: "idle" })}
      onTest={async () => ({ status: "valid" })}
      onSubmit={draft => { setConnections(current => [...current.filter(item => item.provider !== draft.provider), { provider: draft.provider, status: "connected", source: platform ? "platform" : "tenant" }]); setModal(null); }} /> : null}
  </div>;
}
