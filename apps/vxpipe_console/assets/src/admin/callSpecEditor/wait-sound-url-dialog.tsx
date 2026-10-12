import { useId, useState } from "react";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";

export function WaitSoundUrlDialog({ label, initial, validate, onCancel, onSave }: {
  label: string; initial: string; validate: (url: string) => string | undefined;
  onCancel: () => void; onSave: (url: string) => void;
}) {
  const id = useId();
  const [url, setUrl] = useState(initial);
  const [error, setError] = useState<string>();
  return <Dialog open onOpenChange={(open) => !open && onCancel()}>
    <DialogContent>
      <DialogHeader><DialogTitle>{label} audio</DialogTitle><DialogDescription>Enter an HTTP(S) link to an audio file.</DialogDescription></DialogHeader>
      <form className="space-y-4" noValidate onSubmit={(event) => {
        event.preventDefault();
        const value = url.trim();
        const issue = validate(value);
        setError(issue);
        if (!issue) onSave(value);
      }}>
        <div className="space-y-2">
          <label htmlFor={id} className="text-sm font-medium">Audio URL</label>
          <Input id={id} type="url" value={url} placeholder="https://example.com/audio.wav" aria-invalid={!!error} aria-describedby={error ? `${id}-error` : undefined} onChange={(event) => { setUrl(event.target.value); setError(undefined); }} />
          {error && <p id={`${id}-error`} role="alert" className="text-xs text-destructive">{error}</p>}
        </div>
        <DialogFooter><Button type="button" variant="outline" onClick={onCancel}>Cancel</Button><Button type="submit">Use audio</Button></DialogFooter>
      </form>
    </DialogContent>
  </Dialog>;
}
