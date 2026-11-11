import { useEffect, useState } from "react";
import { Plug } from "lucide-react";
import { Button } from "../Button";
import { FormMessage } from "./FormField";
import { type AuthenticationApi, type ConnectedClient, isSessionExpired } from "./authenticationApi";

export function ConnectedClients({ api, onSessionExpired, headingLevel = 2, onManage }: {
  api: AuthenticationApi;
  onSessionExpired?: () => void;
  headingLevel?: 1 | 2;
  onManage?: () => void;
}) {
  const [connections, setConnections] = useState<ConnectedClient[]>();
  const [loadError, setLoadError] = useState<string>();
  const [actionError, setActionError] = useState<string>();
  const [pending, setPending] = useState<string>();
  const [attempt, setAttempt] = useState(0);
  const [notice, setNotice] = useState<string>();
  const Heading = headingLevel === 1 ? "h1" : "h2";
  const ClientHeading = headingLevel === 1 ? "h2" : "h3";

  useEffect(() => {
    let current = true;
    api.connectedClients().then(({ connections }) => {
      if (current) setConnections(connections);
    }).catch((error: unknown) => {
      if (!current) return;
      if (isSessionExpired(error)) onSessionExpired?.();
      setLoadError(error instanceof Error ? error.message : "Connections could not be loaded. Try again.");
    });
    return () => { current = false; };
  }, [api, attempt, onSessionExpired]);

  async function revoke(connection: ConnectedClient) {
    setPending(connection.public_id);
    setActionError(undefined);
    setNotice(undefined);
    try {
      await api.revokeConnectedClient(connection.public_id);
      setConnections((items) => items?.filter((item) => item.public_id !== connection.public_id));
      setNotice(`Access revoked for ${connection.client_name}. Connect again from the client to restore access.`);
    } catch (error: unknown) {
      if (isSessionExpired(error)) onSessionExpired?.();
      setActionError(error instanceof Error ? error.message : "Access could not be revoked. Try again.");
    } finally {
      setPending(undefined);
    }
  }

  return (
    <section className={`access-connections${headingLevel === 1 ? " access-connections-page" : ""}`} aria-labelledby="connected-clients-title">
      <div className="access-section-heading">
        <Heading id="connected-clients-title">Connected clients</Heading>
        {onManage ? <a className="access-connections-manage" href="#/account/connections" onClick={(event) => { event.preventDefault(); onManage(); }}>Manage connected clients</a> : null}
      </div>
      <p className="access-muted">MCP clients you have allowed to act on your behalf. Revoking access prevents further requests from this client.</p>
      {loadError ? <div><FormMessage error>{loadError}</FormMessage><Button onClick={() => { setLoadError(undefined); setAttempt((value) => value + 1); }}>Retry</Button></div> : null}
      {!connections && !loadError ? <p className="access-muted" role="status">Loading connections…</p> : null}
      {connections?.length === 0 ? <p className="access-muted">No connected clients.</p> : null}
      {actionError ? <FormMessage error>{actionError}</FormMessage> : null}
      {notice ? <p className="access-message access-revoked" role="status">{notice}</p> : null}
      <ul className="access-connection-list">
        {connections?.map((connection) => (
          <li key={connection.public_id}>
            <Plug className="access-connection-icon" size={22} aria-hidden />
            <div className="access-connection-info">
              <ClientHeading>{connection.client_name}</ClientHeading>
              <p className="access-muted access-connection-resource">{connection.resource}</p>
              <p className="access-muted">Connected {date(connection.inserted_at)} · Expires {date(connection.expires_at)}</p>
            </div>
            <Button className="access-revoke" disabled={pending !== undefined} aria-label={`Revoke access for ${connection.client_name}`} onClick={() => { void revoke(connection); }}>
              {pending === connection.public_id ? "Revoking…" : "Revoke access"}
            </Button>
          </li>
        ))}
      </ul>
    </section>
  );
}

function date(value: string): string {
  return new Date(value).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}
