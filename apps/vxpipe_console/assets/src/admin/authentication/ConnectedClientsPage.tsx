import { ConnectedClients } from "./ConnectedClients";
import type { AuthenticationApi } from "./authenticationApi";

export function ConnectedClientsPage({ api }: { api: AuthenticationApi }) {
  return <main className="access-page access-clients-page"><ConnectedClients api={api} headingLevel={1} /></main>;
}
