import { SetupServiceCard } from "../SetupServiceCard";
import { setupProviders, type SetupConnection, type SetupProvider, type SetupProviderId } from "../setupCatalog";

export function ConnectedProviders({ connections, providers = setupProviders, platformConnections = [], platform = false, readOnly = false, canManagePlatform = false, query = "", onManage, onRemove }: {
  connections: SetupConnection[];
  providers?: SetupProvider[];
  platformConnections?: SetupConnection[];
  platform?: boolean;
  readOnly?: boolean;
  canManagePlatform?: boolean;
  query?: string;
  onManage: (provider: SetupProviderId) => void;
  onRemove?: (provider: SetupProviderId) => void;
}) {
  return <>{[false, true].map(telephony => {
    const label = telephony ? "Telephony" : "AI services";
    const matches = providers.filter(provider => provider.capabilities.includes("telephony") === telephony
      && connections.some(connection => connection.provider === provider.id)
      && provider.name.toLowerCase().includes(query));
    return <section key={label} className="service-directory-group connected-integrations-group" aria-label={label}>
      <h2>{label}</h2>
      <div className="service-directory-list">
        {matches.map(provider => {
          const connection = connections.find(item => item.provider === provider.id)!;
          const overrides = !platform && connection.source !== "platform" && platformConnections.some(item => item.provider === provider.id);
          return <SetupServiceCard key={provider.id} layout="row" provider={provider} connection={connection}
            platform={platform} overridesPlatform={overrides} readOnly={readOnly || (!platform && connection.source === "platform" && !canManagePlatform)} onSelect={() => onManage(provider.id)}
            onRemoveCredentials={onRemove && (platform || connection.source !== "platform") && !overrides ? () => onRemove(provider.id) : undefined} />;
        })}
        {!matches.length && <p className="connected-integrations-empty">{query ? "No matching integrations." : `No ${telephony ? "telephony" : "AI"} integrations connected.`}</p>}
      </div>
    </section>;
  })}</>;
}
