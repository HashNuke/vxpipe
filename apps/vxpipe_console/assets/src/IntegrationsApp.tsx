import type { ComponentProps } from "react";
import { useLocation } from "react-router";
import { ScopedServicesApp } from "./ScopedServicesApp";
import { IntegrationsDirectory } from "./admin/integrations/IntegrationsDirectory";

/** Production directory presentation with the existing native credential lifecycle. */
export function IntegrationsApp({ canManageMcps = false, actorId, onAuthorizationRedirect, ...props }: Omit<ComponentProps<typeof ScopedServicesApp>, "renderInventory"> & { canManageMcps?: boolean; actorId?: string; onAuthorizationRedirect?: (url: string) => void }) {
  const location = useLocation();
  const tenantKey = props.scope.kind === "tenant" ? props.scope.tenantKey : null;
  return <ScopedServicesApp {...props} showTelephonyApplications={location.pathname.endsWith("/telephony")}
    renderInventory={({ revision, onManage, onRemove, removingProvider }) => <IntegrationsDirectory tenantKey={tenantKey} actorId={actorId} onAuthorizationRedirect={onAuthorizationRedirect} csrfToken={props.csrfToken} canEdit={props.canEdit ?? true} canEditApplications={props.canEditApplications ?? props.canEdit ?? true} canManageMcps={canManageMcps}
      onRemove={onRemove} removingProvider={removingProvider} fetchImpl={props.fetchImpl} onSessionExpired={props.onSessionExpired} revision={revision}
      onManage={(provider, connection) => onManage(provider, connection?.name)} />} />;
}
