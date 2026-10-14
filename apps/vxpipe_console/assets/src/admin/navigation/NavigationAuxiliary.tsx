import { useState } from "react";
import { AdminLayoutContext } from "../AdminLayoutContext";
import { OnboardingPage } from "../OnboardingPage";
import { readyOnboardingState } from "../onboardingFixtures";
import { TenantServicesPage } from "../TenantServicesPage";
import { serviceFixture, applyCredentialCreation } from "../serviceFixtures";
import { ApiKeysSetupPage } from "../ApiKeysSetupPage";
import type { ApiKeyCreation, TenantApiKey } from "../tenantApiKeys";
import { SampleRecipesPage } from "../SampleRecipesPage";
import type { SetupProviderId, SetupTenant } from "../setupCatalog";
import type { SampleRecipe } from "../sampleRecipes";
export function NavigationAuxiliary({ page, tenant, onNavigate, readOnly = false, canReadKeys = true, keys = [], onKeysChange }: { keys?: TenantApiKey[]; onKeysChange?: (keys: TenantApiKey[]) => void; canReadKeys?: boolean; readOnly?: boolean; page: string; tenant: SetupTenant; onNavigate: (path: string) => void }) {
  const [services, setServices] = useState(() => ({ ...serviceFixture("populated"), tenant }));
  const [creation, setCreation] = useState<ApiKeyCreation>({ status: "idle" });
  const [provider, setProvider] = useState<SetupProviderId>("google");
  const [installed, setInstalled] = useState<SampleRecipe["id"][]>([]);
  const [samplesInstalled, setSamplesInstalled] = useState(false);
  return <AdminLayoutContext.Provider value={true}>
    {page === "getting-started" ? <OnboardingPage state={{ ...readyOnboardingState, samples: { ...readyOnboardingState.samples, status: samplesInstalled ? "complete" : "ready" } }} onInstallSamples={() => setSamplesInstalled(true)} onManageServices={() => onNavigate(`/t/${tenant.key}/services`)} />
    : page === "legacy-services" ? <TenantServicesPage canReadCredentials={canReadKeys} canConnect={!readOnly} state={services} onCreateCredential={draft => setServices(current => applyCredentialCreation(current, draft))} onTestCredential={async () => ({ status: "valid" })} />
    : page === "api-keys" ? <main className="tenant-setup"><ApiKeysSetupPage tenantName={tenant.name} onSelectTenant={() => onNavigate(`/t/${tenant.key}/dashboard`)} readOnly={readOnly} keys={keys} creation={creation} onCreate={(name, kind) => { const key = { id: `example-${keys.length + 1}`, name, kind, lastFour: "-key", createdAt: new Date().toISOString() }; onKeysChange?.([...keys, key]); setCreation({ status: "created", key, secret: "storybook-nonfunctional-example-key" }); }} /></main>
    : <main className="tenant-setup"><SampleRecipesPage tenantName={tenant.name} connections={[{ provider: "deepgram", status: "connected" }, { provider: "google", status: "connected" }]} installed={installed} modelProvider={provider} onModelProvider={setProvider} onServices={() => onNavigate(`/t/${tenant.key}/services`)} onTry={recipe => setInstalled(current => [...new Set([...current, recipe.id])])} /></main>}
  </AdminLayoutContext.Provider>;
}
