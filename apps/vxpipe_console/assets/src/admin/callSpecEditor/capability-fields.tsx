import type { CatalogCapability, ModelCatalog } from "../modelCatalog";
import { ChoiceField, TextField } from "./editor-fields";
import { recommendedSelection, selectionForModel } from "./seed";
import type { CapabilitySelection, SourceIssue } from "./types";

type Props = {
  kind: CatalogCapability;
  path: string[];
  value?: CapabilitySelection;
  onChange: (value: CapabilitySelection | undefined) => void;
  catalog: ModelCatalog;
  disabled?: boolean;
  issues?: SourceIssue[];
  defaultLabel?: string;
  defaultDisabled?: boolean;
};

/** Public model and voice remain separate; adapters own their wire-format mapping. */
export function CapabilityFields({ kind, path, value, onChange, catalog, disabled, issues, defaultLabel = "Use default", defaultDisabled = false }: Props) {
  const providers = catalog[kind] ?? {};
  const models = value && Object.hasOwn(providers, value.provider) ? providers[value.provider]! : [];
  const model = models.find((model) => model.id === value?.model);
  const voices = model?.voices;
  const voice = voices && value?.options?.[voices.parameter];
  return <fieldset disabled={disabled} className="grid min-w-0 gap-4 [&_[data-field-path]]:space-y-1.5 [&_[data-slot=label]]:text-xs [&_[data-slot=label]]:text-muted-foreground">
    <div className="grid grid-cols-2 items-start gap-3">
      <ChoiceField label="Provider" path={[...path, "provider"]} issues={issues} disabled={disabled}
        value={value?.provider ?? ""} choices={[{ value: "", label: defaultLabel, disabled: defaultDisabled }, ...Object.keys(providers).sort().map((provider) => ({ value: provider, label: provider }))]}
        onChange={(provider) => onChange(provider ? recommendedSelection(catalog, kind, provider) : undefined)} />
      <ChoiceField label="Model" path={[...path, "model"]} issues={issues} disabled={disabled || !value} value={value?.model ?? ""}
        choices={value ? models.map((model) => ({ value: model.id, label: model.name })) : [{ value: "", label: "Choose provider first", disabled: true }]}
        onChange={(id) => {
          const selected = models.find((model) => model.id === id);
          if (selected && value) {
            const next = { ...value };
            delete next.options;
            onChange({ ...next, ...selectionForModel(value.provider, selected) });
          }
        }} />
    </div>
    {value && <>
      {voices && (voices.type === "free_text"
        ? <TextField label="Voice" path={[...path, "options", voices.parameter]} issues={issues} disabled={disabled} value={typeof voice === "string" ? voice : ""}
          onChange={(voice) => onChange({ ...value, options: { ...value.options, [voices.parameter]: voice } })} />
        : <ChoiceField label="Voice" path={[...path, "options", voices.parameter]} issues={issues} disabled={disabled} value={typeof voice === "string" ? voice : ""}
          choices={voices.values.map((voice) => ({ value: voice.id, label: voice.name }))}
          onChange={(voice) => onChange({ ...value, options: { ...value.options, [voices.parameter]: voice } })} />)}
    </>}
  </fieldset>;
}
