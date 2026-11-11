import { ConnectedClients } from "./ConnectedClients";
import type { AuthenticationApi } from "./authenticationApi";

export function ConnectedClientsPage({ api, onSessionExpired }: { api: AuthenticationApi; onSessionExpired?: () => void }) {
  return <main className="access-page access-clients-page"><ConnectedClients api={api} onSessionExpired={onSessionExpired} headingLevel={1} /></main>;
}
