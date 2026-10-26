import { CheckCheck, CircleAlert } from "lucide-react";
import { Button } from "../Button";
import type { ConnectionLoadState } from "./remoteDirectory";

export function DirectoryAction({ name, status, state, readOnly, unavailable, onSelect }: {
  name: string;
  status?: "connected" | "attention";
  state: ConnectionLoadState;
  readOnly: boolean;
  unavailable?: boolean;
  onSelect: () => void;
}) {
  if (state !== "ready") return null;
  const action = status ? "Edit" : "Connect";
  return <div className="directory-row-actions">
    {status === "connected" && <span className="setup-service-status" title="Connected">
      <CheckCheck size={18} aria-hidden /><span className="sr-only">Connected</span>
    </span>}
    {status === "attention" && <span className="mcp-status-warning directory-attention"><CircleAlert size={16} aria-hidden />Reconnect required</span>}
    <Button disabled={readOnly || (!status && unavailable)} aria-label={`${action} ${name}`} onClick={event => { event.currentTarget.focus(); onSelect(); }}>{action}</Button>
  </div>;
}
