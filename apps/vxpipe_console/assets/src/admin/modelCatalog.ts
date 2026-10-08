export const catalogCapabilities = [
  "speech_to_text", "output_speech_to_text", "text_to_speech",
  "speech_to_speech", "model_inference",
] as const;
export type CatalogCapability = (typeof catalogCapabilities)[number];
export type ModelVoice = { id: string; name: string; default: boolean };
export type ModelVoices =
  | { type: "free_text"; default: string; parameter: string }
  | { type: "list"; values: ModelVoice[]; parameter: string };
export type ModelDescriptor = {
  id: string;
  name: string;
  default: boolean;
  voices: ModelVoices | null;
  tool_support?: boolean;
  context_limit?: number | null;
  options?: Record<string, string | number | boolean | null>;
};
export type ModelCatalog = Partial<Record<CatalogCapability, Record<string, ModelDescriptor[]>>>;

const record = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const text = (value: unknown): value is string =>
  typeof value === "string" && value.length > 0 && value.length <= 512;
const named = (value: unknown): value is ModelVoice & Record<string, unknown> =>
  record(value) && text(value.id) && text(value.name) && typeof value.default === "boolean";
const oneDefault = (values: ModelVoice[]) =>
  values.length > 0 && values.filter((value) => value.default).length === 1 &&
  new Set(values.map((value) => value.id)).size === values.length;

function voices(value: unknown): value is ModelVoices | null {
  if (value === null) return true;
  if (!record(value) || !text(value.parameter)) return false;
  if (value.type === "free_text") return text(value.default);
  return value.type === "list" && Array.isArray(value.values) &&
    value.values.length <= 10000 && value.values.every(named) && oneDefault(value.values);
}

function model(value: unknown): value is ModelDescriptor {
  return named(value) && record(value) && voices(value.voices) &&
    (value.options === undefined || (record(value.options) && Object.values(value.options).every((option) =>
      option === null || typeof option === "string" || typeof option === "boolean" || (typeof option === "number" && Number.isFinite(option))))) &&
    (value.tool_support === undefined || typeof value.tool_support === "boolean") &&
    (value.context_limit === undefined || value.context_limit === null ||
      (typeof value.context_limit === "number" && Number.isSafeInteger(value.context_limit) && value.context_limit > 0));
}

export function parseModelCatalog(value: unknown): ModelCatalog {
  if (!record(value) || !Object.entries(value).every(([capability, providers]) =>
    catalogCapabilities.some((known) => known === capability) && record(providers) &&
    Object.keys(providers).length <= 32 && Object.values(providers).every((models) =>
      Array.isArray(models) && models.length <= 10000 && models.every(model) && oneDefault(models)),
  )) throw new Error("Model catalog could not be loaded. Retry to load the available models.");
  return value as ModelCatalog;
}
