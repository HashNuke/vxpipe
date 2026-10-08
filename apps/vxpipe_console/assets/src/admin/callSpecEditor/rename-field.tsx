import { useState } from "react";
import { TextField } from "./editor-fields";
import { useActionFailure } from "./action-failure-context";
export function RenameField({ name, label, path, disabled, onRename }: { name: string; label: string; path: string[]; disabled?: boolean; onRename: (name: string) => void }) {
  const [draft, setDraft] = useState(name);
  const [error, setError] = useState("");
  const reportFailure = useActionFailure();
  function commit() {
    try { if (draft !== name) onRename(draft); setError(""); }
    catch (error) { setError(error instanceof Error ? error.message : "That name could not be changed."); reportFailure("Couldn't rename. Check the name and try again."); }
  }
  return <div onBlur={commit} onKeyDown={(event) => { if (event.key === "Enter") { event.preventDefault(); commit(); } }}>
    <TextField label={label} path={path} disabled={disabled} value={draft} onChange={setDraft} />
    {error && <p role="alert" className="mt-1 text-xs text-destructive">{error}</p>}
  </div>;
}
