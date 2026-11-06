import type { Meta, StoryObj } from "@storybook/react-vite";
import { useMemo } from "react";
import { MemoryRouter } from "react-router";
import { IntegrationsApp } from "../../IntegrationsApp";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { setupProviders } from "../setupCatalog";

/** Exercise production components with local fixture responses, never real HTTP. */
function fixtureFetch(readOnly: boolean, removalFails: boolean) {
  let connected = true;
  const fetchImpl = async (input: RequestInfo | URL, init?: RequestInit) => {
    if (init?.method === "DELETE") {
      if (removalFails) return Response.json({ error: { code: "in_use" } }, { status: 409 });
      connected = false;
      return new Response(null, { status: 204 });
    }
    const binding = { provider: "google", name: "secondary", source: "platform", status: "connected",
      credential_id: "fixture-google", platform_available: false, saved_fields: ["api_key"], last_validated_at: null };
    const bindings = connected ? [binding] : [];
    const url = new URL(String(input), "https://console.example.test");
    if (url.pathname.endsWith("/integrations")) {
      const providers = setupProviders.filter(provider => url.searchParams.get("category") === "connected" ? connected && provider.id === "google" : true);
      return Response.json({ tenant: null, installation_version: "0.1.0", directory_status: "local", page: null, fallback_items: [],
        connections: bindings.map(item => ({ ...item, can_edit: !readOnly })),
        local_items: providers.map(provider => ({ id: `provider-${provider.id}`, kind: "provider", name: provider.name,
          connection: { provider_id: provider.id }, can_connect: !readOnly,
          connections: provider.id === "google" ? bindings.map(item => ({ ...item, can_edit: !readOnly })) : [] })),
      });
    }
    return Response.json({ tenant: null, bindings, model_catalog: modelCatalogFixture,
      provider_capabilities: Object.fromEntries(setupProviders.map(provider => [provider.id, provider.id === "google" ? ["credential", "llm"] : ["credential", ...provider.capabilities]])) });
  };
  return fetchImpl;
}

function Preview({ readOnly = false, removalFails = false }: { readOnly?: boolean; removalFails?: boolean }) {
  const fetchImpl = useMemo(() => fixtureFetch(readOnly, removalFails), [readOnly, removalFails]);
  return <MemoryRouter initialEntries={["/platform/services"]}><IntegrationsApp scope={{ kind: "platform" }} csrfToken="fixture" fetchImpl={fetchImpl} canEdit={!readOnly} onNavigate={() => undefined} /></MemoryRouter>;
}

const meta = {
  title: "Vxpipe/Console/Integrations/Production native inventory",
  component: Preview,
  parameters: { layout: "fullscreen", docs: { description: { component: "Production native inventory and credential components with in-memory fixture responses. No real HTTP requests or stored credentials." } } },
} satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Connected: Story = {};
export const ReadOnly: Story = { args: { readOnly: true } };
export const RemovalFailure: Story = { args: { removalFails: true } };
