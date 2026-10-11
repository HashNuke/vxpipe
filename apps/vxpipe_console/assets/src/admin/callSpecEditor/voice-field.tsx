import { useEffect, useId, useMemo, useRef, useState } from "react";
import { AudioLines, ChevronRight } from "lucide-react";
import { Button } from "../components/ui/button";
import { Label } from "../components/ui/label";
import type { Voice, VoiceCatalogClient, VoiceScope } from "../voiceCatalog";
import { useIssueField } from "./issue-context";
import type { SourceIssue } from "./types";
import { VoicePicker } from "./voice-picker";

type Props = VoiceScope & { client: VoiceCatalogClient; value: string; onChange: (id: string) => void; path: string[]; issues?: SourceIssue[]; disabled?: boolean };
export function VoiceField({ client, provider, model, capability, value, onChange, path, issues, disabled }: Props) {
  const id = useId();
  const trigger = useRef<HTMLButtonElement>(null);
  const { ref, errors } = useIssueField(path, issues);
  const scope = useMemo(() => ({ provider, model, capability }), [provider, model, capability]);
  const identity = `${provider}/${model}/${capability}/${value}`;
  const [resolved, setResolved] = useState<{ identity: string; voice: Voice | null }>();
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const controller = new AbortController();
    client.get(scope, value, controller.signal).then(voice => {
      if (!controller.signal.aborted) setResolved({ identity, voice });
    }).catch(() => { if (!controller.signal.aborted) setResolved({ identity, voice: null }); });
    return () => controller.abort();
  }, [client, scope, value, identity]);
  const voice = resolved?.identity === identity ? resolved.voice : undefined;
  const name = voice?.name || value || "Choose voice";
  return <div ref={ref} tabIndex={-1} data-field-path={JSON.stringify(path)} className="space-y-1.5 outline-none">
    <Label htmlFor={id} className="text-xs text-muted-foreground">Voice</Label>
    <Button ref={trigger} id={id} variant="outline" className="h-auto min-h-12 w-full justify-start gap-3 py-2 text-left" disabled={disabled}
      aria-label={`Voice: ${name}`} aria-haspopup="dialog" aria-invalid={errors.length > 0} aria-describedby={errors.length ? `${id}-errors` : undefined} onClick={() => setOpen(true)}>
      <AudioLines className="size-4 shrink-0 text-muted-foreground" />
      <span className="min-w-0 flex-1"><span className="block truncate">{name}</span>
        {voice?.attributes.length ? <span className="block truncate text-xs font-normal text-muted-foreground">{voice.attributes.slice(0, 3).map(attribute => attribute.value).join(" · ")}</span> : null}
      </span><span className="text-xs text-muted-foreground">Change</span><ChevronRight className="size-4" />
    </Button>
    {voice === null && value && <p className="text-xs text-muted-foreground">Saved voice. Its details aren’t available in this catalog.</p>}
    {!!errors.length && <div id={`${id}-errors`} className="text-xs text-destructive">{errors.map((issue, index) => <p key={index}>{issue.reason}</p>)}</div>}
    {open && <VoicePicker key={identity} client={client} scope={scope} current={voice ?? (value ? { id: value, name: value, attributes: [] } : undefined)}
      onReturnFocus={() => trigger.current?.focus()} onClose={() => setOpen(false)} onSelect={selected => { setResolved({ identity: `${provider}/${model}/${capability}/${selected.id}`, voice: selected }); onChange(selected.id); setOpen(false); }} />}
  </div>;
}
