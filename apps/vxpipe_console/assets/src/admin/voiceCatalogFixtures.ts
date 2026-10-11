import type { Voice, VoiceCatalogClient, VoiceCatalogDescriptor, VoiceFilters, VoiceScope } from "./voiceCatalog";

// UI-review data, not a live inventory or a provider-availability claim.
// Filter keys/types follow provider docs; example metadata and demo IDs are illustrative.
const languages = [{ value: "en", label: "English" }, { value: "hi", label: "Hindi" }, { value: "es", label: "Spanish" }];
const genders = [{ value: "feminine", label: "Feminine" }, { value: "masculine", label: "Masculine" }, { value: "gender_neutral", label: "Gender neutral" }];
type Entry = Voice & { facets: VoiceFilters };
const voice = (id: string, name: string, description: string, facets: VoiceFilters, attributes: string[]): Entry => ({
  id, name, description, facets, attributes: attributes.map((value, index) => ({ key: String(index), label: "Voice property", value })),
});
const cartesia = [
  voice("db6b0ed5-d5d3-463d-ae85-518a07d3c2b4", "Skylar", "A friendly, conversational voice for customer support.", { language: "en", gender: "feminine", is_owner: false }, ["English", "American", "Feminine"]),
  voice("demo-cartesia-rowan", "Rowan", "Measured delivery with a warm, steady tone.", { language: "en", gender: "masculine", is_owner: false }, ["English", "British", "Masculine"]),
  voice("demo-cartesia-anaya", "Anaya", "Bright and clear, with a relaxed conversational pace.", { language: "hi", gender: "feminine", is_owner: false }, ["Hindi", "Feminine"]),
  voice("demo-cartesia-lucia", "Lucía", "Expressive delivery for everyday conversations.", { language: "es", gender: "feminine", is_owner: false }, ["Spanish", "Feminine"]),
  voice("demo-cartesia-river", "River", "An even, approachable voice with a light touch.", { language: "en", gender: "gender_neutral", is_owner: true }, ["English", "Gender neutral", "Workspace voice"]),
  voice("demo-cartesia-skylar-custom", "Skylar", "A workspace voice with the same display name.", { language: "en", gender: "feminine", is_owner: true }, ["English", "Feminine", "Workspace voice"]),
];
const elevenlabs = [
  voice("JBFqnCBsd6RMkjVDRZzb", "George", "Warm narration with a composed delivery.", { language: ["en"], gender: "male", accent: "british", category: "premade", min_notice_period_days: 0 }, ["English", "British", "Male", "Premade"]),
  voice("demo-elevenlabs-maya", "Maya", "An expressive multilingual voice for conversation.", { language: ["en", "hi"], gender: "female", accent: "indian", category: "professional", min_notice_period_days: 30 }, ["English / Hindi", "Indian", "Female", "Professional"]),
  voice("demo-elevenlabs-alex", "Alex", "A clear, neutral voice for short responses.", { language: ["en", "es"], gender: "male", accent: "american", category: "generated", min_notice_period_days: 60 }, ["English / Spanish", "American", "Male", "Generated"]),
];
const names = (values: string[]) => values.map(name => ({ id: name, name, attributes: [], facets: {} }));
const descriptors: Record<string, Omit<VoiceCatalogDescriptor, "modelName">> = {
  cartesia: { providerName: "Cartesia", search: true, filters: [
    { key: "language", label: "Language", type: "select", options: languages },
    { key: "gender", label: "Gender", type: "select", options: genders },
    { key: "is_owner", label: "Workspace voices only", type: "boolean" },
  ] },
  elevenlabs: { providerName: "ElevenLabs", search: true, filters: [
    { key: "language", label: "Languages", type: "multi_select", options: languages },
    { key: "category", label: "Category", type: "select", options: ["premade", "cloned", "generated", "professional"].map(value => ({ value, label: value.charAt(0).toUpperCase() + value.slice(1) })) },
    { key: "accent", label: "Accent", type: "text", placeholder: "e.g. british" },
    { key: "gender", label: "Gender", type: "select", options: [{ value: "female", label: "Female" }, { value: "male", label: "Male" }] },
    { key: "min_notice_period_days", label: "Minimum notice (days)", type: "number", min: 0 },
  ] },
  google: { providerName: "Google", search: true, filters: [] },
  openai: { providerName: "OpenAI", search: true, filters: [] },
  deepgram: { providerName: "Deepgram", search: true, filters: [
    { key: "accent", label: "Accent", type: "select", options: [{ value: "american", label: "American" }, { value: "british", label: "British" }] },
  ] },
  rime: { providerName: "Rime", search: true, filters: [
    { key: "gender", label: "Gender", type: "select", options: [{ value: "Female", label: "Female" }, { value: "Male", label: "Male" }] },
    { key: "age", label: "Age", type: "select", options: [{ value: "Young Adult", label: "Young adult" }, { value: "Middle Aged", label: "Middle aged" }] },
  ] },
};
const entries: Record<string, Entry[]> = {
  cartesia, elevenlabs,
  google: [voice("Kore", "Kore", "Firm", {}, []), voice("Puck", "Puck", "Upbeat", {}, []), voice("Aoede", "Aoede", "Breezy", {}, [])],
  openai: names(["marin", "cedar", "alloy", "ash"]),
  deepgram: [voice("hannah", "Hannah", "Clear and thoughtful.", { accent: "american" }, ["American", "Female", "Young"]), voice("kit", "Kit", "Friendly and energetic.", { accent: "british" }, ["British", "Male", "Young adult"])],
  rime: [voice("astra", "Astra", "Bright and expressive.", { gender: "Female", age: "Young Adult" }, ["Female", "Young adult"]), voice("cupola", "Cupola", "Confident, with a warm delivery.", { gender: "Male", age: "Middle Aged" }, ["Male", "Middle aged"])],
};
const publicVoice = (item: Entry): Voice => ({ id: item.id, name: item.name, description: item.description, attributes: item.attributes });
function matches(item: Entry, filters: VoiceFilters) {
  return Object.entries(filters).every(([key, value]) => {
    const actual = item.facets[key];
    if (typeof value === "number") return typeof actual === "number" && actual >= value;
    if (Array.isArray(value)) return value.some(entry => Array.isArray(actual) ? actual.includes(entry) : actual === entry);
    return typeof value === "string" && typeof actual === "string" ? actual.toLowerCase() === value.toLowerCase() : actual === value;
  });
}
const modelName = (scope: VoiceScope) => ({ "sonic-3.6": "Sonic 3.6", eleven_flash_v2_5: "Eleven Flash v2.5", flux: "Flux", "gemini-3.1-flash-tts-preview": "Gemini 3.1 Flash TTS", coda: "Coda", "gpt-live-1": "GPT-Live 1" })[scope.model] ?? scope.model;
export function fixtureVoiceCatalog({ fail = false, loading = false }: { fail?: boolean; loading?: boolean } = {}): VoiceCatalogClient {
  return {
    describe: async scope => ({ ...(descriptors[scope.provider] ?? { providerName: scope.provider, search: true, filters: [] }), modelName: modelName(scope) }),
    get: async (scope, id) => { const item = entries[scope.provider]?.find(voice => voice.id === id); return item ? publicVoice(item) : null; },
    list: async (scope, query, signal) => {
      if (loading) await new Promise<never>((_resolve, reject) => { if (signal.aborted) reject(new DOMException("Aborted", "AbortError")); else signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), { once: true }); });
      if (fail) throw new Error("Fixture catalog unavailable");
      const search = query.search.toLowerCase().trim();
      const matched = (entries[scope.provider] ?? []).filter(item => matches(item, query.filters) && [item.id, item.name, item.description ?? "", ...item.attributes.map(a => a.value)].join(" ").toLowerCase().includes(search));
      const start = Number(query.cursor ?? 0), end = start + 4;
      return { voices: matched.slice(start, end).map(publicVoice), nextCursor: end < matched.length ? String(end) : null, total: matched.length };
    },
  };
}
export const storyVoiceCatalog = fixtureVoiceCatalog();
