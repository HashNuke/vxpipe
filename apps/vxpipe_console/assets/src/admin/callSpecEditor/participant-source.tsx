import { useState, type ReactNode } from "react";
import { Code } from "lucide-react";
import { Button } from "../components/ui/button";
import { applyJson } from "./json-edits";
import { JsonEditor } from "./json-editor";
import { useJsonDrafts } from "./json-drafts";
import { stringifySourceJson } from "./source-json";
import type { InspectorProps } from "./inspectorTypes";

export function ParticipantSource({ document, onChange, participantKey, heading, actions, children, focusRequest }: InspectorProps & {
  participantKey: string; heading: ReactNode; actions?: ReactNode; children: ReactNode;
}) {
  const { drafts, setDraft } = useJsonDrafts();
  const scope = `participant:${participantKey}`;
  const draft = drafts[scope];
  const [view, setView] = useState<{ key: string; json: boolean; request?: number }>();
  const json = focusRequest && view?.request !== focusRequest.id ? false : view?.key === participantKey ? view.json : !!draft;
  const value = Object.hasOwn(document.source.participants, participantKey) ? stringifySourceJson(document.source.participants[participantKey], 2)! : "";
  return <>
    <div className="flex shrink-0 items-center justify-between gap-3 p-4 pb-2">
      <div className="flex min-w-0 items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">{heading}</div>
      <div className="flex items-center gap-1">
        <Button variant="outline" size="sm" className="aria-pressed:border-primary aria-pressed:bg-selection aria-pressed:text-primary" aria-label="Participant JSON" aria-pressed={json} onClick={() => setView({ key: participantKey, json: !json, request: focusRequest?.id })}><Code className="h-4 w-4" />JSON{draft ? " •" : ""}</Button>
        {actions}
      </div>
    </div>
    {json ? <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto p-4">
      <div><h3 className="break-all text-sm font-semibold">{participantKey}</h3><p className="mt-1 text-xs text-muted-foreground">{document.readOnly ? "Participant JSON is read-only." : "Edit this participant, including model and provider options."}</p></div>
      <JsonEditor key={participantKey} label="Participant JSON" value={value} draft={draft} readOnly={document.readOnly}
        onDraftChange={(draft) => setDraft(scope, draft)} onApply={(text) => onChange(applyJson(document, text, participantKey))} />
    </div> : children}
  </>;
}
