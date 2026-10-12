import { useState } from "react";
import { Button } from "../components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { TextField } from "./editor-fields";
import { VariableSchemaFields } from "./variable-schema-fields";
import { addSection, renameSection, setSectionSchema } from "./variables";
import type { InspectorProps } from "./inspectorTypes";
import type { VariableSchema } from "./types";

export function VariableSectionModal({ document, onChange, issues, previousName, onClose, returnFocus }: InspectorProps & { previousName?: string; onClose: () => void; returnFocus: () => void }) {
  const [name, setName] = useState(previousName ?? "");
  const [schema, setSchema] = useState<VariableSchema>(() => previousName === undefined
    ? { type: "object", properties: {}, additionalProperties: false }
    : structuredClone(document.source.call_variables!.sections![previousName]!.schema));
  const [error, setError] = useState<string>();
  const path = ["call_variables", "sections", previousName ?? name];
  function save() {
    try {
      if (!name.trim()) throw new Error("Enter a section name.");
      const next = previousName === undefined ? addSection(document, name, { schema })
        : setSectionSchema(renameSection(document, previousName, name), name, schema);
      onChange(next);
      onClose();
    } catch (failure) { setError(failure instanceof Error ? failure.message : "Could not save this section."); }
  }
  return <Dialog open onOpenChange={(open) => { if (!open) onClose(); }}><DialogContent aria-describedby={undefined} className="flex max-h-[calc(100dvh-2rem)] flex-col overflow-hidden rounded-md p-0 [&>button]:flex [&>button]:size-9 [&>button]:items-center [&>button]:justify-center [&>button]:top-2 [&>button]:right-2" onCloseAutoFocus={(event) => { event.preventDefault(); returnFocus(); }}>
    <DialogHeader className="shrink-0 border-b border-border p-4 pr-12 text-left"><DialogTitle>{document.readOnly ? "View section" : previousName === undefined ? "Add section" : "Edit section"}</DialogTitle></DialogHeader>
    <div className="min-h-0 space-y-5 overflow-y-auto p-4">
      <TextField label="Section name" path={path} value={name} disabled={document.readOnly} issues={issues} onChange={(next) => { setName(next); setError(undefined); }} />
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <VariableSchemaFields root hideProperties label={previousName ?? "New section"} path={[...path, "schema"]} value={schema} disabled={document.readOnly} issues={issues} onChange={setSchema} />
    </div>
    <DialogFooter className="shrink-0 border-t border-border p-4"><Button variant="outline" onClick={onClose}>{document.readOnly ? "Close" : "Cancel"}</Button>{!document.readOnly && <Button onClick={save}>{previousName === undefined ? "Add section" : "Save section"}</Button>}</DialogFooter>
  </DialogContent></Dialog>;
}
