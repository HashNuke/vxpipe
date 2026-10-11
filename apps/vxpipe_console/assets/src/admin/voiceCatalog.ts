import { createContext } from "react";

/** Authoring contract; provider wire formats and credentials stay behind this boundary. */
export type VoiceScope = { provider: string; model: string; capability: "text_to_speech" | "speech_to_speech" };
export type Voice = {
  id: string;
  name: string;
  description?: string;
  attributes: { key: string; label: string; value: string }[];
};
type FilterBase = { key: string; label: string };
export type VoiceFilter = FilterBase & (
  | { type: "select" | "multi_select"; options: { value: string; label: string }[] }
  | { type: "text"; placeholder?: string }
  | { type: "boolean" }
  | { type: "number"; min?: number; max?: number }
);
export type VoiceFilters = Record<string, string | string[] | boolean | number>;
export type VoiceCatalogDescriptor = { providerName: string; modelName: string; search: boolean; filters: VoiceFilter[] };
export type VoiceCatalogQuery = { search: string; filters: VoiceFilters; cursor: string | null };
export type VoiceCatalogPage = { voices: Voice[]; nextCursor: string | null; total?: number };
export type VoiceCatalogClient = {
  describe: (scope: VoiceScope, signal: AbortSignal) => Promise<VoiceCatalogDescriptor>;
  list: (scope: VoiceScope, query: VoiceCatalogQuery, signal: AbortSignal) => Promise<VoiceCatalogPage>;
  get: (scope: VoiceScope, id: string, signal: AbortSignal) => Promise<Voice | null>;
};

// Storybook supplies a fixture adapter. Production keeps the existing field until
// the authorized provider catalog endpoints implement this contract.
export const VoiceCatalogContext = createContext<VoiceCatalogClient | null>(null);
