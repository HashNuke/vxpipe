import { useId, useState } from "react";
import { Button } from "../components/ui/button";
import { Textarea } from "../components/ui/textarea";
import type { JsonDraft } from "./json-drafts";

export function JsonEditor({ label, value, draft, onDraftChange, onApply, readOnly = false }: {
  label: string; value: string; draft?: JsonDraft; onDraftChange: (draft: JsonDraft | undefined) => void;
  onApply: (text: string) => void; readOnly?: boolean;
}) {
  const [error, setError] = useState("");
  const errorId = useId();
  const stale = draft && draft.base !== value;
  const message = stale ? "The source changed while you were editing. Copy your edits, then discard this JSON draft to load the current source." : error;
  return <div className="flex min-h-0 flex-1 flex-col gap-3">
    <Textarea aria-label={label} value={draft?.text ?? value} readOnly={readOnly} spellCheck={false} autoCapitalize="off" autoCorrect="off"
      aria-invalid={!!message} aria-describedby={message ? errorId : undefined}
      className="min-h-64 flex-1 field-sizing-fixed resize-none font-mono text-xs leading-relaxed"
      onChange={(event) => { setError(""); const text = event.target.value; onDraftChange(text === value ? undefined : { text, base: draft?.base ?? value }); }} />
    {message && <p role="alert" id={errorId} className="max-h-36 shrink-0 overflow-auto whitespace-pre-wrap break-words text-sm text-destructive">{message}</p>}
    {!readOnly && <div className="flex shrink-0 flex-wrap items-center gap-2">
      <Button size="sm" disabled={!draft || !!stale} onClick={() => {
        try { onApply(draft!.text); onDraftChange(undefined); setError(""); }
        catch (error) { setError(error instanceof Error ? error.message : "Couldn't apply JSON. Your edits are still here."); }
      }}>Apply JSON</Button>
      <Button variant="outline" size="sm" disabled={!draft} onClick={() => { onDraftChange(undefined); setError(""); }}>Discard JSON changes</Button>
      <p className="w-full text-xs text-muted-foreground">Apply to update the draft, then save the call spec.</p>
    </div>}
  </div>;
}
