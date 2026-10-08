import { Checkbox } from "../components/ui/checkbox";
import { Label } from "../components/ui/label";
import { ChoiceField } from "./editor-fields";
import { setMediaPolicy } from "./edits";
import type { InspectorProps } from "./inspectorTypes";
import type { MediaPolicy } from "./types";

export function MediaPolicyFields({ document, onChange, issues, participantKey }: InspectorProps & { participantKey: string | null }) {
  const policy = participantKey === null ? document.source.media_policy : document.source.participants[participantKey]?.while_present;
  const path = participantKey === null ? ["media_policy"] : ["participants", participantKey, "while_present"];
  const keys = Object.keys(document.source.participants);
  const defaultLabel = participantKey === null ? "Default" : "Inherit";
  function change(edit: (next: MediaPolicy) => void) {
    const next = structuredClone(policy ?? {}); edit(next);
    onChange(setMediaPolicy(document, participantKey, Object.keys(next).length ? next : undefined));
  }
  return <fieldset disabled={document.readOnly} className="space-y-5">
    <p className="text-xs text-muted-foreground">{participantKey === null ? "Choose call-wide permissions. Default keeps the runtime's policy." : "These overrides apply while this participant is present. Inherit keeps the call-wide policy."}</p>
    {(["record_audio", "save_transcripts"] as const).map((key) => <ChoiceField key={key} label={key === "record_audio" ? "Record audio" : "Save transcripts"} path={[...path, key]} issues={issues} disabled={document.readOnly}
      value={policy?.[key] === undefined ? "" : policy[key] ? "allow" : "deny"} choices={[{ value: "", label: defaultLabel }, { value: "allow", label: "Allow" }, { value: "deny", label: "Deny" }]}
      onChange={(value) => change((next) => { if (!value) delete next[key]; else next[key] = value === "allow"; })} />)}
    {(["audio_routes", "transcript_routes"] as const).map((kind) => {
      const routes = policy?.[kind];
      const label = kind === "audio_routes" ? "Audio" : "Transcripts";
      return <section key={kind} className="space-y-4 border-t pt-4">
        <ChoiceField label={`${label === "Audio" ? "Audio" : "Transcript"} routing`} path={[...path, kind]} issues={issues} disabled={document.readOnly}
          value={routes === undefined ? "" : "restricted"} choices={[{ value: "", label: defaultLabel }, { value: "restricted", label: "Restricted" }]}
          onChange={(mode) => change((next) => { if (!mode) delete next[kind]; else next[kind] = {}; })}
          hint="Restricted routing permits only the selected pairs. An empty selection sends nothing." />
        {routes !== undefined && [...new Set([...keys, ...Object.keys(routes)])].map((from) => {
          const targets = Object.hasOwn(routes, from) ? routes[from]! : [];
          const title = `${label} from ${from}`;
          const otherKeys = keys.filter((key) => key !== from);
          const mode = !targets.length ? "none" : targets.length === otherKeys.length && otherKeys.every((key) => targets.includes(key)) ? "all" : "selected";
          return <div key={from} className="space-y-3 rounded-md border p-3">
            <ChoiceField label={title} path={[...path, kind, from]} issues={issues} disabled={document.readOnly} value={mode}
              choices={[{ value: "none", label: "Nobody" }, { value: "all", label: "All other participants" }, { value: "selected", label: "Selected participants", disabled: true }]}
              onChange={(mode) => change((next) => { next[kind] = { ...next[kind], [from]: mode === "none" ? [] : keys.filter((key) => key !== from) }; })} />
            <div className="flex flex-wrap gap-x-4 gap-y-2">{[...new Set([...keys, ...targets])].map((to) => <Label key={to} className="text-xs"><Checkbox disabled={document.readOnly} checked={targets.includes(to)} aria-label={`${title} to ${to}`} onCheckedChange={(checked) => change((next) => {
              const map = next[kind] ?? {};
              const destinations = Object.hasOwn(map, from) ? map[from]! : [];
              next[kind] = { ...map, [from]: checked === true ? [...new Set([...destinations, to])] : destinations.filter((key) => key !== to) };
            })} />{to}</Label>)}</div>
          </div>;
        })}
      </section>;
    })}
  </fieldset>;
}
