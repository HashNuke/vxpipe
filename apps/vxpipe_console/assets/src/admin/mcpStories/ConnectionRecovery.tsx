import { CircleAlert, KeyRound } from "lucide-react";
import { Button } from "../Button";
import { CopyField } from "./FormControls";
import { callbackUrl } from "./fixtures";

/** Proposed outcomes of live discovery; all actions stay inside the preview. */
export function ConnectionRecovery({ registration, name, endpoint, onEdit, onRetry, onClose }: {
  registration: boolean; name: string; endpoint: string;
  onEdit: () => void; onRetry: () => void; onClose: () => void;
}) {
  return <>
    <div className="mcp-dialog-scroll mcp-recovery">
      {registration ? <KeyRound size={24} aria-hidden /> : <CircleAlert size={24} aria-hidden />}
      <div>
        <h3>{registration ? "Register VxPipe with your provider" : "Could not discover authentication"}</h3>
        <p>{registration
          ? `${name} requires an OAuth client registered with its provider. Add this callback URL there, then enter the client details here.`
          : "The server’s authentication settings could not be loaded. Check the server URL, retry, or enter the settings supplied by your provider."}</p>
      </div>
      <dl className="mcp-details"><div><dt>MCP server URL</dt><dd>{endpoint}</dd></div></dl>
      {registration && <CopyField label="Callback URL" value={callbackUrl} />}
    </div>
    <footer className="mcp-dialog-footer">
      <Button onClick={onClose}>Cancel</Button>
      {!registration && <Button onClick={onEdit}>Edit connection</Button>}
      <Button className="mcp-primary" onClick={registration ? onEdit : onRetry}>{registration ? "Enter client details" : "Try again"}</Button>
    </footer>
  </>;
}
