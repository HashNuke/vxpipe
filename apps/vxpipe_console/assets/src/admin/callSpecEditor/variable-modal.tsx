import { useState } from "react";
import { Button } from "../components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { IssueAnchor } from "./issue-anchor";
import { TextField } from "./editor-fields";
import { validateVariableEnums } from "./variable-enum-values";
import { VariableSchemaFields } from "./variable-schema-fields";
import { renameVariableField, setVariableField } from "./variables";
import type { InspectorProps } from "./inspectorTypes";
import type { VariableSchema } from "./types";

export function VariableModal({ document, onChange, issues, sectionKey, previousName, onClose, returnFocus }: InspectorProps & { sectionKey: string; previousName?: string; onClose: () => void; returnFocus: () => void }) {
  const section = document.source.call_variables!.sections![sectionKey]!;
  const [name, setName] = useState(previousName ?? "");
  const [schema, setSchema] = useState<VariableSchema>(() => previousName === undefined ? { type: "string" } : structuredClone(section.schema.properties![previousName]!));
  const [required, setRequired] = useState(previousName !== undefined && (section.schema.required?.includes(previousName) ?? false));
  const [error, setError] = useState<string>();
  const label = `${sectionKey} / ${previousName ?? "new variable"}`;
  const path = ["call_variables", "sections", sectionKey, "schema", "properties", previousName ?? name];
  function save() {
    try {
      if (!name.trim()) throw new Error("Enter a variable name.");
      if (name !== previousName && Object.hasOwn(section.schema.properties ?? {}, name)) throw new Error("That variable already exists. Choose a different name.");
      const enumError = validateVariableEnums(schema);
      if (enumError) throw new Error(enumError);
      const renamed = previousName !== undefined && previousName !== name ? renameVariableField(document, sectionKey, previousName, name) : document;
      onChange(setVariableField(renamed, sectionKey, name, schema, required));
      onClose();
    } catch (failure) { setError(failure instanceof Error ? failure.message : "Could not save this variable."); }
  }
  return <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}><DialogContent aria-describedby={undefined} className="flex max-h-[calc(100dvh-2rem)] flex-col gap-0 overflow-hidden rounded-md p-0 [&>button]:flex [&>button]:size-9 [&>button]:items-center [&>button]:justify-center [&>button]:top-2 [&>button]:right-2" onCloseAutoFocus={(event) => { event.preventDefault(); returnFocus(); }}>
    <DialogHeader className="shrink-0 border-b border-border p-4 pr-12 text-left"><DialogTitle>{document.readOnly ? "View variable" : previousName === undefined ? "Add variable" : "Edit variable"}</DialogTitle></DialogHeader>
    <div className="min-h-0 space-y-4 overflow-y-auto p-4">
      <TextField layout="responsive-inline" labelClassName="sm:w-24" label="Name" path={[...path, "$name"]} value={name} disabled={document.readOnly} issues={issues} onChange={(next) => { setName(next); setError(undefined); }} />
      {(issues ?? []).filter(issue => path.every((part, index) => issue.path[index] === part) && ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "minLength", "maxLength", "minItems", "maxItems", "nullable", "additionalProperties"].includes(issue.path.at(-1) ?? "")).map((issue, index) =>
        <IssueAnchor key={index} path={issue.path} issues={[issue]} className="text-xs text-muted-foreground outline-none focus-visible:ring-2 focus-visible:ring-ring"><p>Update this constraint in the JSON editor.</p></IssueAnchor>)}
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <VariableSchemaFields label={label} path={path} value={schema} onChange={(next) => { setSchema(next); setError(undefined); }} required={required} onRequiredChange={setRequired} disabled={document.readOnly} issues={issues} />
    </div>
    <DialogFooter className="shrink-0 border-t border-border p-4"><Button variant="outline" onClick={onClose}>{document.readOnly ? "Close" : "Cancel"}</Button>{!document.readOnly && <Button onClick={save}>{previousName === undefined ? "Add variable" : "Save variable"}</Button>}</DialogFooter>
  </DialogContent></Dialog>;
}
