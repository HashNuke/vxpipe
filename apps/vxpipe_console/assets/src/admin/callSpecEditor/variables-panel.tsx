import { useRef, useState } from "react";
import { ChevronDown, Eye, Pencil, Plus, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "../components/ui/collapsible";
import { RenameField } from "./rename-field";
import { VariableSchemaFields } from "./variable-schema-fields";
import { VariableModal } from "./variable-modal";
import { IssueAnchor } from "./issue-anchor";
import { useIssueRequest } from "./issue-context";
import { addSection, removeSection, renameSection, removeVariableField, setSectionSchema } from "./variables";
import type { InspectorProps } from "./inspectorTypes";
import type { ReactNode } from "react";

export function VariablesPanel(props: InspectorProps) {
  const { document, onChange, issues } = props;
  const sections = document.source.call_variables?.sections ?? {};
  const [editing, setEditing] = useState<{ section: string; name?: string } | null>(null);
  const trigger = useRef<HTMLButtonElement | null>(null);
  const request = useIssueRequest();
  const [dismissedRequest, setDismissedRequest] = useState<number>();
  const requestedSection = request?.path[0] === "call_variables" && request.path[1] === "sections" ? request.path[2] : undefined;
  const requestedName = request?.path[3] === "schema" && request.path[4] === "properties" ? request.path[5] : undefined;
  const revealed = request && request.id !== dismissedRequest && requestedSection && requestedName && Object.hasOwn(sections, requestedSection) && Object.hasOwn(sections[requestedSection]!.schema.properties ?? {}, requestedName)
    ? { section: requestedSection, name: requestedName } : null;
  const selected = editing ?? revealed;
  return <div className="space-y-4">
    <div className="flex items-center justify-between gap-3"><h3 className="text-sm font-semibold">Call variables</h3><Button variant="outline" size="sm" disabled={document.readOnly} onClick={() => {
      let index = 1; while (Object.hasOwn(sections, `section_${index}`)) index++;
      onChange(addSection(document, `section_${index}`));
    }}><Plus />Add section</Button></div>
    <p className="text-xs text-muted-foreground">Group the information your agents collect. Set section access in each agent’s Variables tab.</p>
    {!Object.keys(sections).length && <p className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">Add a section to define the information agents can collect and share.</p>}
    {Object.entries(sections).map(([key, section]) => <section key={key} aria-label={`Section ${key}`} className="min-w-0 rounded-md border border-border bg-card">
      <div className="flex items-end gap-2 border-b border-border p-3"><div className="min-w-0 flex-1"><RenameField name={key} label={`Section ${key} name`} displayLabel="Section name" path={["call_variables", "sections", key]} disabled={document.readOnly} onRename={(next) => onChange(renameSection(document, key, next))} /></div>
        <Button variant="ghost" size="icon" disabled={document.readOnly} aria-label={`Remove section ${key}`} onClick={() => onChange(removeSection(document, key))}><Trash2 /></Button></div>
      <ul className="divide-y divide-border">
        {Object.entries(section.schema.properties ?? {}).map(([name, schema]) => <li key={name}>
          <IssueAnchor path={["call_variables", "sections", key, "schema", "properties", name]} issues={issues}>
            <div className="flex min-w-0 items-center gap-2 px-3 py-2">
              <div className="min-w-0 flex-1"><p className="wrap-anywhere font-mono text-sm font-medium">{name}</p><p className="text-xs text-muted-foreground">{Array.isArray(schema.type) ? schema.type.join(" or ") : schema.type ?? "Any type"}{section.schema.required?.includes(name) ? " · Required" : " · Optional"}</p></div>
              <Button variant="ghost" size="icon" aria-label={`${document.readOnly ? "View" : "Edit"} ${key} / ${name}`} onClick={(event) => { trigger.current = event.currentTarget; setEditing({ section: key, name }); }}>{document.readOnly ? <Eye /> : <Pencil />}</Button>
              <Button variant="ghost" size="icon" disabled={document.readOnly} aria-label={`Remove ${key} / ${name}`} onClick={() => onChange(removeVariableField(document, key, name))}><Trash2 /></Button>
            </div>
          </IssueAnchor>
        </li>)}
      </ul>
      {!Object.keys(section.schema.properties ?? {}).length && <p className="px-3 py-4 text-sm text-muted-foreground">No variables yet. Add the first variable to this section.</p>}
      <div className="border-t border-border p-3"><Button variant="outline" size="sm" disabled={document.readOnly} aria-label={`Add variable to ${key}`} onClick={(event) => { trigger.current = event.currentTarget; setEditing({ section: key }); }}><Plus />Add variable</Button></div>
      <SectionConstraints requestId={requestedSection === key && !requestedName ? request?.id : undefined}><VariableSchemaFields root hideProperties label={key} path={["call_variables", "sections", key, "schema"]} value={section.schema} disabled={document.readOnly} issues={issues} onChange={(schema) => onChange(setSectionSchema(document, key, schema))} />
      </SectionConstraints>
    </section>)}
    {selected && <VariableModal key={`${selected.section}:${selected.name ?? "new"}:${request?.id ?? "manual"}`} {...props} sectionKey={selected.section} previousName={selected.name} returnFocus={() => trigger.current?.focus()} onClose={() => { setEditing(null); setDismissedRequest(request?.id); }} />}
  </div>;
}

function SectionConstraints({ requestId, children }: { requestId?: number; children: ReactNode }) {
  const [expanded, setExpanded] = useState(false);
  const [dismissedRequest, setDismissedRequest] = useState<number>();
  return <Collapsible className="border-t border-border p-3" open={expanded || (requestId !== undefined && requestId !== dismissedRequest)} onOpenChange={(open) => { setExpanded(open); if (!open) setDismissedRequest(requestId); }}>
    <CollapsibleTrigger asChild><Button variant="ghost" size="sm">Section constraints<ChevronDown /></Button></CollapsibleTrigger>
    <CollapsibleContent className="pt-3">{children}</CollapsibleContent>
  </Collapsible>;
}
