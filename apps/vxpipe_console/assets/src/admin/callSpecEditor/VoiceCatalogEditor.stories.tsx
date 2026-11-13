import { useMemo } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { createMemoryRouter, RouterProvider } from "react-router";
import { CallSpecEditorRoute } from "../../CallSpecEditorRoute";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import type { CatalogCapability } from "../modelCatalog";
import { newCallSpec } from "./seed";
import type { EditorFetch } from "./editor-api";
import { StoryNavigationContext, storyNavigation } from "../stories/storyNavigation";

/** The production route and HTTP client, with offline responses at the fetch boundary. */
function Editor() {
  const router = useMemo(() => {
    const fetch = createPreviewFetch();
    return createMemoryRouter([{ path: "/admin/tenants/:tenantKey/call-specs/:callSpecId", element: <CallSpecEditorRoute csrfToken="storybook" fetchImpl={fetch} /> }], { initialEntries: ["/admin/tenants/demo/call-specs/reception"] });
  }, []);
  return <StoryNavigationContext value={storyNavigation("/t/demo/editor", () => {}, { key: "demo", name: "Demo" })}><RouterProvider router={router} /></StoryNavigationContext>;
}
function createPreviewFetch(): EditorFetch {
  const source = newCallSpec(modelCatalogFixture, { direction: "incoming" }).source;
  source.name = "Reception voice settings";
  if (source.participants.assistant?.type === "agent") source.participants.assistant.prompt = "Help callers book an appointment.";
  const selection = { provider: "elevenlabs", model: "eleven_flash_v2_5", credential_name: "office", options: { voice: "saved-private-voice" } };
  source.defaults!.capabilities!.text_to_speech = selection;
  source.opening_audio = { type: "text", text: "Welcome to our office", text_to_speech: selection };
  let saved = { source, call_spec_id: "reception", revision: 1, latest_revision: 1, published_revision: 1 };
  const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });
  const fetch: EditorFetch = async (input, init) => {
    const url = new URL(String(input), "https://console.example.test");
    if (url.pathname.includes("/voices")) {
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(resolve, 400);
        init?.signal?.addEventListener("abort", () => { clearTimeout(timer); reject(new DOMException("Cancelled", "AbortError")); }, { once: true });
      });
      if (url.searchParams.get("search") === "error") return reply({}, 503);
      const voice = { id: "river", name: "River", attributes: [{ key: "language", label: "Language", value: "English" }] };
      if (url.pathname.endsWith("/descriptor")) return reply({ providerName: "ElevenLabs", modelName: "Flash v2.5", search: true, filters: [{ key: "language", label: "Language", type: "text" }] });
      if (url.pathname.endsWith("/voices")) {
        const page = url.searchParams.has("cursor") ? [{ ...voice, id: "long-name", name: "A very long friendly voice name for reception and customer care conversations" }] : [voice];
        return reply({ voices: url.searchParams.get("search") === "missing" ? [] : page, nextCursor: url.searchParams.has("cursor") || url.searchParams.get("search") ? null : "second" });
      }
      const id = decodeURIComponent(url.pathname.split("/").at(-1)!);
      return reply({ voice: { ...voice, id, name: id === "saved-private-voice" ? "Private reception voice" : id === "river" ? "River" : "Selected voice" } });
    }
    if (url.pathname.endsWith("/call-spec-editor-lookups")) return reply({ credential_names: { elevenlabs: ["office"] }, telephony_services: [], mcp_integrations: [], tool_catalog: { tools: [], mcp_available: true } });
    if (url.pathname.includes("/providers")) {
      const providers = modelCatalogFixture[url.searchParams.get("capability") as CatalogCapability] ?? {};
      return url.pathname.endsWith("/models") ? reply({ models: providers[url.pathname.split("/").at(-2)!] }) : reply({ providers: Object.keys(providers).map(id => ({ id, credential_available: true })) });
    }
    if (init?.method === "PUT") saved = { ...saved, source: JSON.parse(String(init.body)).source, revision: saved.revision + 1, latest_revision: saved.revision + 1 };
    if (init?.method === "POST") saved = { ...saved, published_revision: saved.revision };
    return reply({ call_spec: saved });
  };
  return fetch;
}

const meta = { title: "Vxpipe/Console/Call spec editor/Voice catalog API", component: Editor, parameters: { layout: "fullscreen" } } satisfies Meta<typeof Editor>;
export default meta;
export const ProductionClient: StoryObj<typeof meta> = {};
