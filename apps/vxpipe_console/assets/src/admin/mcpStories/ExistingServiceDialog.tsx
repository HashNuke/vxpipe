import { Button } from "../Button";
import { SetupDialog } from "../SetupDialog";

export type ExistingService = {
  name: string;
  inherited?: boolean;
  needsAttention?: boolean;
};

export function ExistingServiceDialog({ service, tenantName, platform, onClose, onViewServices }: {
  service: ExistingService;
  tenantName: string;
  platform: boolean;
  onClose: () => void;
  onViewServices: () => void;
}) {
  const state = service.needsAttention ? "configured" : "connected";
  return <div className="existing-service-notice">
    <SetupDialog title={`Already ${state}`} onClose={onClose} anchorTop>
      <div className="mcp-dialog-scroll">
        <p>{service.name} is already {state} {platform ? "for the platform" : `for ${tenantName}`}{service.inherited && !platform ? " through platform services" : ""}.</p>
        {service.needsAttention && <p className="mcp-hint">Open connected integrations to update the connection.</p>}
      </div>
      <footer className="mcp-dialog-footer">
        <Button onClick={onClose}>Close</Button>
        <Button className="mcp-primary" onClick={onViewServices}>View connected integrations</Button>
      </footer>
    </SetupDialog>
  </div>;
}
