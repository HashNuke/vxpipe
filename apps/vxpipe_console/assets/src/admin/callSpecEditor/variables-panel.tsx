import { Plus, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { RenameField } from "./rename-field";
import { VariableSchemaFields } from "./variable-schema-fields";
import { SectionPermissionMatrix } from "./section-permission-matrix";
import { addSection, removeSection, renameSection, renameVariableField, removeVariableField, setSectionSchema } from "./variables";
import type { InspectorProps } from "./inspectorTypes";

/** Adapts Callpipe's collected-variable rows to section-owned JSON Schema fields. */
export function VariablesPanel({ document, onChange, issues }: InspectorProps) {
  const sections = document.source.call_variables?.sections ?? {};
  return <div className="space-y-6">
    <div className="flex items-center justify-between gap-3"><h3 className="text-sm font-semibold">Call Variables</h3><Button variant="outline" size="sm" disabled={document.readOnly} onClick={() => {
      let index = 1; while (Object.hasOwn(sections, `section_${index}`)) index++;
      onChange(addSection(document, `section_${index}`));
    }}><Plus />Add section</Button></div>
    {!Object.keys(sections).length && <p className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">Add a section to define the information agents can collect and share.</p>}
    {Object.entries(sections).map(([key, section]) => <section key={key} aria-label={`Section ${key}`} className="space-y-4 border-t pt-4">
      <div className="flex items-end gap-2"><div className="min-w-0 flex-1"><RenameField name={key} label={`Section ${key} name`} path={["call_variables", "sections", key]} disabled={document.readOnly} onRename={(next) => onChange(renameSection(document, key, next))} /></div>
        <Button variant="ghost" size="icon" disabled={document.readOnly} aria-label={`Remove section ${key}`} onClick={() => onChange(removeSection(document, key))}><Trash2 /></Button></div>
      <VariableSchemaFields root label={key} path={["call_variables", "sections", key, "schema"]} value={section.schema} disabled={document.readOnly} issues={issues}
        onChange={(schema) => onChange(setSectionSchema(document, key, schema))}
        onRenameProperty={(previous, next) => onChange(renameVariableField(document, key, previous, next))}
        onRemoveProperty={(field) => onChange(removeVariableField(document, key, field))} />
    </section>)}
    <SectionPermissionMatrix document={document} onChange={onChange} issues={issues} />
  </div>;
}
