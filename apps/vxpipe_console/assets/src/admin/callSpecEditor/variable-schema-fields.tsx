import { Plus, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { Checkbox } from "../components/ui/checkbox";
import { Label } from "../components/ui/label";
import { ChoiceField, TextField } from "./editor-fields";
import { RenameField } from "./rename-field";
import { VariableEnumInput } from "./variable-enum-input";
import { variableType } from "./variable-enum-values";
import type { SourceIssue, VariableSchema, VariableType } from "./types";
const types: VariableType[] = ["string", "number", "integer", "boolean", "object", "array"];
type Props = { value: VariableSchema; onChange: (value: VariableSchema) => void; label: string; path: string[]; disabled?: boolean; issues?: SourceIssue[]; root?: boolean; required?: boolean; onRequiredChange?: (required: boolean) => void; hideProperties?: boolean; onRenameProperty?: (previous: string, next: string) => void; onRemoveProperty?: (key: string) => void };

/** Schema controls retain omitted keywords and every unedited nested schema. */
export function VariableSchemaFields({ value, onChange, label, path, disabled, issues, root, required, onRequiredChange, hideProperties, onRenameProperty, onRemoveProperty }: Props) {
  const base = variableType(value);
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
  return <div className="min-w-0 space-y-4 empty:hidden">
    {!root && <>
      <ChoiceField {...common} layout="responsive-inline" labelClassName="sm:w-24" label={`${label} type`} displayLabel="Type" path={[...path, "type"]} value={base ?? ""}
        choices={[{ value: "", label: "Any type" }, ...types.map((type) => ({ value: type, label: type }))]}
        onChange={(type) => { if (!type) remove("type"); else patch({ type: type as VariableType, ...(type === "object" && base !== "object" && value.additionalProperties === undefined ? { additionalProperties: false } : {}) }); }} />
      <div className="space-y-4">
        {onRequiredChange && <Label className="gap-3 text-sm"><span className="w-24">Required?</span><Checkbox disabled={disabled} checked={required} aria-label={`${label} required`} onCheckedChange={(checked) => onRequiredChange(checked === true)} /></Label>}
        <Label className="gap-3 text-sm"><span className="w-24">Enum?</span><Checkbox disabled={disabled} checked={value.enum !== undefined} aria-label={`${label} enum`} onCheckedChange={(checked) => checked ? patch({ enum: [] }) : remove("enum")} /></Label>
      </div>
      {value.enum !== undefined && <VariableEnumInput {...common} key={base ?? "any"} label={label} path={[...path, "enum"]} type={base} value={value.enum} onChange={(values) => patch({ enum: values })} />}
    </>}
    {!hideProperties && (base === "object" || value.properties !== undefined || root) && <div className="space-y-3">
      {Object.entries(value.properties ?? {}).map(([key, schema]) => <div key={key} className="space-y-3 rounded-md border border-border/70 bg-card p-3">
        <div className="flex items-end gap-2"><div className="min-w-0 flex-1"><RenameField layout="responsive-inline" labelClassName="sm:w-24" name={key} label={`${label} / ${key} name`} displayLabel="Name" path={[...path, "properties", key, "$name"]} disabled={disabled} onRename={(next) => renameProperty(key, next)} /></div>
          <Button variant="ghost" size="icon" disabled={disabled} aria-label={`Remove ${label} / ${key}`} onClick={() => removeProperty(key)}><Trash2 /></Button></div>
        <VariableSchemaFields {...common} label={`${label} / ${key}`} path={[...path, "properties", key]} value={schema} onChange={(next) => patch({ properties: { ...value.properties, [key]: next } })}
          required={value.required?.includes(key) ?? false} onRequiredChange={(checked) => patch({ required: checked ? [...(value.required ?? []).filter((name) => name !== key), key] : (value.required ?? []).filter((name) => name !== key) })} />
      </div>)}
      <Button variant="outline" size="sm" disabled={disabled} aria-label={`Add ${label} field`} onClick={() => { let index = 1; while (Object.hasOwn(value.properties ?? {}, `field_${index}`)) index++; patch({ properties: { ...value.properties, [`field_${index}`]: { type: "string" } } }); }}><Plus />Add field</Button>
    </div>}
    {(value.required ?? []).filter((key) => !Object.hasOwn(value.properties ?? {}, key)).map((key, index) => <div key={index} className="flex items-end gap-2">
      <TextField {...common} label={`${label} undeclared required field ${index + 1}`} path={[...path, "required"]} value={key} onChange={(next) => patch({ required: value.required!.map((name) => name === key ? next : name) })} />
      <Button variant="ghost" size="icon" disabled={disabled} aria-label={`Remove required ${key}`} onClick={() => patch({ required: value.required!.filter((name) => name !== key) })}><Trash2 /></Button>
    </div>)}
    {(base === "array" || value.items !== undefined) && <section className="space-y-3 border-t pt-3"><div className="flex items-center justify-between gap-2"><h3 className="text-sm font-medium">Array items</h3>
      <Button variant="ghost" size="sm" disabled={disabled} onClick={() => value.items === undefined ? patch({ items: {} }) : remove("items")}>{value.items === undefined ? "Define items" : "Clear items"}</Button></div>
      {value.items && <VariableSchemaFields {...common} label={`${label} / items`} path={[...path, "items"]} value={value.items} onChange={(items) => patch({ items })} />}
    </section>}
  </div>;
}
