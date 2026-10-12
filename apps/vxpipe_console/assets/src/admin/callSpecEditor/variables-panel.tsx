import { useRef, useState } from "react";
import { Eye, List, Pencil, Plus, Trash2 } from "lucide-react";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { VariableModal } from "./variable-modal";
import { VariableSectionModal } from "./variable-section-modal";
import { IssueAnchor } from "./issue-anchor";
import { useIssueRequest } from "./issue-context";
import { removeSection, removeVariableField } from "./variables";
import { stringifySourceJson } from "./source-json";
import type { InspectorProps } from "./inspectorTypes";
import type { VariableSchema } from "./types";

type Editing = { kind: "section"; name?: string } | { kind: "variable"; section: string; name?: string };

export function VariablesPanel(props: InspectorProps) {
  const { document, onChange, issues } = props;
  const sections = document.source.call_variables?.sections ?? {};
  const [editing, setEditing] = useState<Editing | null>(null);
  const trigger = useRef<HTMLButtonElement | null>(null);
  const addTrigger = useRef<HTMLButtonElement | null>(null);
  const request = useIssueRequest();
  const [dismissedRequest, setDismissedRequest] = useState<number>();
  const requestedSection = request?.path[0] === "call_variables" && request.path[1] === "sections" ? request.path[2] : undefined;
  const requestedName = request?.path[3] === "schema" && request.path[4] === "properties" ? request.path[5] : undefined;
  const revealed: Editing | null = request && request.id !== dismissedRequest && requestedSection && Object.hasOwn(sections, requestedSection)
    ? requestedName && Object.hasOwn(sections[requestedSection]!.schema.properties ?? {}, requestedName)
      ? { kind: "variable", section: requestedSection, name: requestedName }
      : { kind: "section", name: requestedSection }
    : null;
  const selected = editing ?? revealed;
  const modal = { ...props, returnFocus: () => (trigger.current?.isConnected ? trigger.current : addTrigger.current)?.focus(), onClose: () => { setEditing(null); setDismissedRequest(request?.id); } };
  return <div className="space-y-3">
    <div className="flex items-center justify-between gap-3"><h3 className="text-sm font-semibold">Call variables</h3><Button ref={addTrigger} variant="outline" size="sm" disabled={document.readOnly} onClick={(event) => { trigger.current = event.currentTarget; setEditing({ kind: "section" }); }}><Plus />Add section</Button></div>
    <p className="text-xs text-muted-foreground">Group the information your agents collect. Set section access in each agent’s Variables tab.</p>
    {!Object.keys(sections).length && <p className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">Add a section to define the information agents can collect and share.</p>}
    {Object.entries(sections).map(([key, section]) => <section key={key} aria-label={`Section ${key}`} className="min-w-0 rounded-md border border-border bg-card">
      <IssueAnchor path={["call_variables", "sections", key]} issues={issues} className="rounded-t-md border-b border-border bg-muted/70 px-2 py-1">
        <div className="flex items-center gap-2"><List aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" /><div className="flex min-w-0 flex-1 flex-wrap items-center gap-x-2 gap-y-1"><h4 className="wrap-anywhere text-sm font-semibold">{key}</h4><SectionConstraintTags schema={section.schema} /></div>
          <Button variant="ghost" size="icon" className="size-7" disabled={document.readOnly} aria-label={`Add variable to section ${key}`} title="Add variable" onClick={(event) => { trigger.current = event.currentTarget; setEditing({ kind: "variable", section: key }); }}><Plus /></Button>
          <Button variant="ghost" size="icon" className="size-7" aria-label={`${document.readOnly ? "View" : "Edit"} section ${key}`} onClick={(event) => { trigger.current = event.currentTarget; setEditing({ kind: "section", name: key }); }}>{document.readOnly ? <Eye /> : <Pencil />}</Button>
          <Button variant="ghost" size="icon" className="size-7" disabled={document.readOnly} aria-label={`Remove section ${key}`} onClick={() => onChange(removeSection(document, key))}><Trash2 /></Button></div>
      </IssueAnchor>
      <ul className="divide-y divide-border">
        {Object.entries(section.schema.properties ?? {}).map(([name, schema]) => <li key={name}>
          <IssueAnchor path={["call_variables", "sections", key, "schema", "properties", name]} issues={issues}>
            <div className="flex min-w-0 items-center gap-2 py-1 pr-2 pl-7">
              <div className="flex min-w-0 flex-1 flex-wrap items-baseline gap-x-2"><p className="wrap-anywhere font-mono text-sm font-medium">{name}</p><p className="text-xs text-muted-foreground">{Array.isArray(schema.type) ? schema.type.join(" or ") : schema.type ?? "Any type"}{section.schema.required?.includes(name) ? " · Required" : " · Optional"}</p></div>
              <Button variant="ghost" size="icon" className="size-7" aria-label={`${document.readOnly ? "View" : "Edit"} ${key} / ${name}`} onClick={(event) => { trigger.current = event.currentTarget; setEditing({ kind: "variable", section: key, name }); }}>{document.readOnly ? <Eye /> : <Pencil />}</Button>
              <Button variant="ghost" size="icon" className="size-7" disabled={document.readOnly} aria-label={`Remove ${key} / ${name}`} onClick={() => onChange(removeVariableField(document, key, name))}><Trash2 /></Button>
            </div>
          </IssueAnchor>
        </li>)}
      </ul>
      {!Object.keys(section.schema.properties ?? {}).length && <p className="py-2 pr-2 pl-7 text-sm text-muted-foreground">No variables yet. Add the first variable to this section.</p>}
      <div className="border-t border-border py-1 pr-2 pl-7"><Button variant="outline" size="sm" disabled={document.readOnly} className="h-7 text-xs" aria-label={`Add variable to ${key}`} onClick={(event) => { trigger.current = event.currentTarget; setEditing({ kind: "variable", section: key }); }}><Plus />Add variable</Button></div>
    </section>)}
    {selected?.kind === "variable" && <VariableModal key={`${selected.section}:${selected.name ?? "new"}:${request?.id ?? "manual"}`} {...modal} sectionKey={selected.section} previousName={selected.name} />}
    {selected?.kind === "section" && <VariableSectionModal key={`${selected.name ?? "new"}:${request?.id ?? "manual"}`} {...modal} previousName={selected.name} />}
  </div>;
}

function SectionConstraintTags({ schema }: { schema: VariableSchema }) {
  const constraints = Object.entries(schema).filter(([key, value]) => !["type", "properties", "additionalProperties"].includes(key) && value !== undefined && !(Array.isArray(value) && !value.length));
  if (!constraints.length) return null;
  return <div className="flex min-w-0 flex-wrap gap-1">{constraints.map(([key, value]) => <Badge key={key} variant="secondary" className="max-w-full rounded-md whitespace-normal wrap-anywhere text-left">{key}: {stringifySourceJson(value)}</Badge>)}</div>;
}
