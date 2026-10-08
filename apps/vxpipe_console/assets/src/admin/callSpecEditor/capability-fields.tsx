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
  credentialNames: Record<string, string[]>;
  disabled?: boolean;
  issues?: SourceIssue[];
  defaultLabel?: string;
};

/** Public model and voice remain separate; adapters own their wire-format mapping. */
export function CapabilityFields({ kind, path, value, onChange, catalog, credentialNames, disabled, issues, defaultLabel = "Use default" }: Props) {
  const providers = catalog[kind] ?? {};
  const models = value && Object.hasOwn(providers, value.provider) ? providers[value.provider]! : [];
  const model = models.find((model) => model.id === value?.model);
  const voices = model?.voices;
  const names = value && Object.hasOwn(credentialNames, value.provider) ? credentialNames[value.provider]! : [];
  const voice = voices && value?.options?.[voices.parameter];
  return <fieldset disabled={disabled} className="space-y-4">
    <ChoiceField label="Provider" path={[...path, "provider"]} issues={issues} disabled={disabled}
      value={value?.provider ?? ""} choices={[{ value: "", label: defaultLabel }, ...Object.keys(providers).sort().map((provider) => ({ value: provider, label: provider }))]}
      onChange={(provider) => onChange(provider ? recommendedSelection(catalog, kind, provider) : undefined)} />
    {value && <>
      <ChoiceField label="Model" path={[...path, "model"]} issues={issues} disabled={disabled} value={value.model}
        choices={models.map((model) => ({ value: model.id, label: `${model.name}${model.default ? " · Recommended" : ""}` }))}
        onChange={(id) => {
          const selected = models.find((model) => model.id === id);
          if (selected) {
            const next = { ...value };
            delete next.options;
            onChange({ ...next, ...selectionForModel(value.provider, selected) });
          }
        }} />
      {voices && (voices.type === "free_text"
        ? <TextField label="Voice" path={[...path, "options", voices.parameter]} issues={issues} disabled={disabled} value={typeof voice === "string" ? voice : ""}
          hint={`Recommended: ${voices.default}`} onChange={(voice) => onChange({ ...value, options: { ...value.options, [voices.parameter]: voice } })} />
        : <ChoiceField label="Voice" path={[...path, "options", voices.parameter]} issues={issues} disabled={disabled} value={typeof voice === "string" ? voice : ""}
          choices={voices.values.map((voice) => ({ value: voice.id, label: `${voice.name}${voice.default ? " · Recommended" : ""}` }))}
          onChange={(voice) => onChange({ ...value, options: { ...value.options, [voices.parameter]: voice } })} />)}
      <ChoiceField label="Credential" path={[...path, "credential_name"]} issues={issues} disabled={disabled} value={value.credential_name ?? ""}
        choices={[{ value: "", label: "Service default" }, ...names.map((name) => ({ value: name, label: name }))]}
        onChange={(name) => { const next = { ...value }; if (name) next.credential_name = name; else delete next.credential_name; onChange(next); }} />
    </>}
  </fieldset>;
}
