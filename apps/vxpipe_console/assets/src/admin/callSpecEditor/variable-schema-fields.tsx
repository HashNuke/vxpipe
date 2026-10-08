import { Plus, Trash2, ChevronDown } from "lucide-react";
import { Button } from "../components/ui/button";
import { Checkbox } from "../components/ui/checkbox";
import { Label } from "../components/ui/label";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "../components/ui/collapsible";
import { ChoiceField, NumberField, TextField } from "./editor-fields";
import { RenameField } from "./rename-field";
import { ArrayFields } from "./structured-value-fields";
import type { SourceIssue, VariableSchema, VariableType } from "./types";
const types: VariableType[] = ["string", "number", "integer", "boolean", "object", "array", "null"];
const constraints = ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "minLength", "maxLength", "minItems", "maxItems"] as const;
type Props = { value: VariableSchema; onChange: (value: VariableSchema) => void; label: string; path: string[]; disabled?: boolean; issues?: SourceIssue[]; root?: boolean; onRenameProperty?: (previous: string, next: string) => void; onRemoveProperty?: (key: string) => void };

/** Schema controls retain omitted keywords and every unedited nested schema. */
export function VariableSchemaFields({ value, onChange, label, path, disabled, issues, root, onRenameProperty, onRemoveProperty }: Props) {
  const base = Array.isArray(value.type) ? value.type.find((type) => type !== "null") : value.type;
  const nullable = Array.isArray(value.type) && value.type.includes("null");
  const applicable = base === "string" ? ["minLength", "maxLength"] : base === "array" ? ["minItems", "maxItems"] : base === "number" || base === "integer" ? ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"] : base ? [] : constraints;
  const visibleConstraints = constraints.filter((key) => applicable.includes(key) || value[key] !== undefined);
  const common = { disabled, issues };
  function patch(update: Partial<VariableSchema>) { onChange({ ...value, ...update }); }
  function remove(key: keyof VariableSchema) { const next = { ...value }; delete next[key]; onChange(next); }
  function renameProperty(previous: string, next: string) {
    if (previous === next) return;
    if (Object.hasOwn(value.properties ?? {}, next)) throw new Error("That field already exists.");
    if (onRenameProperty) onRenameProperty(previous, next);
    else onChange({ ...value, properties: Object.fromEntries(Object.entries(value.properties ?? {}).map(([key, schema]) => [key === previous ? next : key, schema])), ...(value.required ? { required: value.required.map((key) => key === previous ? next : key) } : {}) });
  }
  function removeProperty(key: string) {
    if (onRemoveProperty) onRemoveProperty(key);
    else {
      const properties = { ...value.properties }; delete properties[key];
      onChange({ ...value, properties, ...(value.required ? { required: value.required.filter((name) => name !== key) } : {}) });
    }
  }
  return <div className="min-w-0 space-y-4">
    {!root && <div className="flex flex-wrap items-end gap-3"><div className="min-w-0 flex-1"><ChoiceField {...common} label={`${label} type`} path={[...path, "type"]} value={base ?? ""}
      choices={[{ value: "", label: "Any type" }, ...types.map((type) => ({ value: type, label: type }))]}
      onChange={(type) => { if (!type) remove("type"); else patch({ type: nullable && type !== "null" ? [type as VariableType, "null"] : type as VariableType }); }} /></div>
      <Label className="pb-2 text-xs"><Checkbox disabled={disabled || !base || base === "null"} checked={nullable} aria-label={`${label} nullable`} onCheckedChange={(checked) => patch({ type: checked ? [base!, "null"] : base })} />Nullable</Label>
    </div>}
    {(base === "object" || value.properties !== undefined || root) && <div className="space-y-3">
      <ChoiceField {...common} label={`${label} additional properties`} path={[...path, "additionalProperties"]} value={value.additionalProperties === undefined ? "" : String(value.additionalProperties)}
        choices={[{ value: "", label: "Schema default" }, { value: "false", label: "Declared fields only" }]}
        onChange={(next) => { if (!next) remove("additionalProperties"); else patch({ additionalProperties: false }); }} />
      {Object.entries(value.properties ?? {}).map(([key, schema]) => <div key={key} className="space-y-3 rounded-md border border-border/70 bg-card p-3">
        <div className="flex items-end gap-2"><div className="min-w-0 flex-1"><RenameField name={key} label={`${label} / ${key} name`} path={[...path, "properties", key, "$name"]} disabled={disabled} onRename={(next) => renameProperty(key, next)} /></div>
          <Button variant="ghost" size="icon" disabled={disabled} aria-label={`Remove ${label} / ${key}`} onClick={() => removeProperty(key)}><Trash2 /></Button></div>
        <VariableSchemaFields {...common} label={`${label} / ${key}`} path={[...path, "properties", key]} value={schema} onChange={(next) => patch({ properties: { ...value.properties, [key]: next } })} />
        <Label className="text-xs"><Checkbox disabled={disabled} checked={value.required?.includes(key) ?? false} aria-label={`${label} / ${key} required`} onCheckedChange={(checked) => patch({ required: checked ? [...(value.required ?? []).filter((name) => name !== key), key] : (value.required ?? []).filter((name) => name !== key) })} />Required</Label>
      </div>)}
      <Button variant="outline" size="sm" disabled={disabled} aria-label={`Add ${label} field`} onClick={() => { let index = 1; while (Object.hasOwn(value.properties ?? {}, `field_${index}`)) index++; patch({ properties: { ...value.properties, [`field_${index}`]: { type: "string" } } }); }}><Plus />Add field</Button>
    </div>}
    {(value.required ?? []).filter((key) => !Object.hasOwn(value.properties ?? {}, key)).map((key, index) => <div key={index} className="flex items-end gap-2">
      <TextField {...common} label={`${label} undeclared required field ${index + 1}`} path={[...path, "required"]} value={key} onChange={(next) => patch({ required: value.required!.map((name) => name === key ? next : name) })} />
      <Button variant="ghost" size="icon" disabled={disabled} aria-label={`Remove required ${key}`} onClick={() => patch({ required: value.required!.filter((name) => name !== key) })}><Trash2 /></Button>
    </div>)}
    {(base === "array" || value.items !== undefined) && <section className="space-y-3 border-t pt-3"><div className="flex items-center justify-between gap-2"><h4 className="text-sm font-medium">Array items</h4>
      <Button variant="ghost" size="sm" disabled={disabled} onClick={() => value.items === undefined ? patch({ items: {} }) : remove("items")}>{value.items === undefined ? "Define items" : "Clear items"}</Button></div>
      {value.items && <VariableSchemaFields {...common} label={`${label} / items`} path={[...path, "items"]} value={value.items} onChange={(items) => patch({ items })} />}
    </section>}
    <ChoiceField {...common} label={`${label} allowed values`} path={[...path, "enum"]} value={value.enum === undefined ? "" : "enum"} choices={[{ value: "", label: "Any value" }, { value: "enum", label: "Enumeration" }]} onChange={(mode) => mode ? patch({ enum: [""] }) : remove("enum")} />
    {value.enum !== undefined && <ArrayFields {...common} label={`${label} enum`} path={[...path, "enum"]} value={value.enum} onChange={(values) => patch({ enum: values })} />}
    {visibleConstraints.length > 0 && <Collapsible defaultOpen={constraints.some((key) => value[key] !== undefined)} className="space-y-3">
      <CollapsibleTrigger asChild><Button variant="ghost" size="sm" aria-label={`Constraints for ${label}`}>Constraints<ChevronDown /></Button></CollapsibleTrigger>
      <CollapsibleContent className="grid grid-cols-1 gap-3 sm:grid-cols-2">{visibleConstraints.map((key) => <NumberField {...common} key={key} label={`${label} ${key}`} path={[...path, key]} value={value[key]} onChange={(next) => next === undefined ? remove(key) : patch({ [key]: next })} />)}</CollapsibleContent>
    </Collapsible>}
  </div>;
}
