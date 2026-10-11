import { useState } from "react";
import { Button } from "../components/ui/button";
import { Checkbox } from "../components/ui/checkbox";
import { Label } from "../components/ui/label";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { TextField } from "./editor-fields";
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
      const renamed = previousName !== undefined && previousName !== name ? renameVariableField(document, sectionKey, previousName, name) : document;
      onChange(setVariableField(renamed, sectionKey, name, schema, required));
      onClose();
    } catch (failure) { setError(failure instanceof Error ? failure.message : "Could not save this variable."); }
  }
  return <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}><DialogContent className="flex max-h-[calc(100dvh-2rem)] flex-col overflow-hidden rounded-md p-0 [&>button]:flex [&>button]:size-9 [&>button]:items-center [&>button]:justify-center [&>button]:top-2 [&>button]:right-2" onCloseAutoFocus={(event) => { event.preventDefault(); returnFocus(); }}>
    <DialogHeader className="shrink-0 border-b border-border p-4 pr-12 text-left"><DialogTitle>{document.readOnly ? "View variable" : previousName === undefined ? "Add variable" : "Edit variable"}</DialogTitle><DialogDescription className="wrap-anywhere">Section: {sectionKey}</DialogDescription></DialogHeader>
    <div className="min-h-0 space-y-4 overflow-y-auto p-4">
      <TextField label="Variable name" path={[...path, "$name"]} value={name} disabled={document.readOnly} issues={issues} onChange={(next) => { setName(next); setError(undefined); }} />
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <VariableSchemaFields label={label} path={path} value={schema} onChange={setSchema} disabled={document.readOnly} issues={issues} />
      <Label className="text-sm"><Checkbox checked={required} disabled={document.readOnly} aria-label={`${label} required`} onCheckedChange={(checked) => setRequired(checked === true)} />Required</Label>
    </div>
    <DialogFooter className="shrink-0 border-t border-border p-4"><Button variant="outline" onClick={onClose}>{document.readOnly ? "Close" : "Cancel"}</Button>{!document.readOnly && <Button onClick={save}>{previousName === undefined ? "Add variable" : "Save variable"}</Button>}</DialogFooter>
  </DialogContent></Dialog>;
}
