import { ArrowUpRight } from "lucide-react";
import { useEffect, useRef, useState } from "react";

import { AdminShell } from "./AdminShell";
import { ApiKeysSetupPage } from "./ApiKeysSetupPage";
import type {
  ApiKeyCreation,
  TenantApiKey,
  TenantApiKeyKind,
} from "./tenantApiKeys";
import { Button } from "./Button";
import {
  CreateTenantModal,
  type TenantCreationStatus,
} from "./CreateTenantModal";
import { RecipeDiagram } from "./RecipeDiagram";
import { SampleRecipesPage } from "./SampleRecipesPage";
import { ServiceSetupModal, type ServiceModalState } from "./ServiceSetupModal";
import { SetupDialog } from "./SetupDialog";
import { TenantSetupOverview } from "./TenantSetupOverview";
import { TenantSetupPage } from "./TenantSetupPage";
import {
  capabilityLabels,
  effectiveSetupConnections,
  voiceSetupReady,
  setupProviders,
  providersFor,
  setupProvider,
  voiceCapabilities,
  type SetupConnection,
  type SetupProviderId,
  type SetupTenant,
} from "./setupCatalog";
import {
  sampleRecipes,
  recipeCapabilities,
  type SampleRecipe,
} from "./sampleRecipes";
import type { CredentialDraft } from "./serviceTypes";
import "./tenantSetup.css";

export type OnboardingScenario =
  | "platform-services"
  | "platform-configured"
  | "platform-telnyx"
  | "inherited-services"
  | "tenant-override"
  | "tenant-override-error"
  | "service-picker"
  | "creating-tenant"
  | "choose-services"
  | "enter-credentials"
  | "validating"
  | "validation-error"
  | "provider-unavailable"
  | "speech-connected"
  | "ready-for-samples"
  | "multiple-providers"
  | "rime"
  | "blocked-samples"
  | "samples"
  | "loading-samples"
  | "sample-error"
  | "complete"
  | "unavailable"
  | "demo-nudge"
  | "multiple-tenants"
  | "renamed-tenant"
  | "telnyx-credentials"
  | "telnyx-ai-only"
  | "telnyx-connected"
  | "new-tenant"
  | "creating-new-tenant"
  | "tenant-creation-error"
  | "new-tenant-setup"
  | "api-keys"
  | "api-key-full-access"
  | "api-key-creating"
  | "api-key-error"
  | "api-key-created"
  | "api-key-existing";

type SetupPage = "services" | "keys" | "samples" | "tenants" | "platform";
const steps: Array<{
  page: Exclude<SetupPage, "tenants" | "platform">;
  label: string;
}> = [
  { page: "services", label: "Setup services" },
  { page: "keys", label: "Create API Keys" },
  { page: "samples", label: "Setup Call Specs" },
];
const exampleApiKey: TenantApiKey = {
  id: "example-key",
  name: "Application",
  kind: "calls",
};

const demoTenant: SetupTenant = {
  key: "demo-tenant",
  name: "Demo",
  demo: true,
};
const connection = (provider: SetupProviderId): SetupConnection => ({
  provider,
  status: "connected",
});
type TenantProgress = {
  connections: SetupConnection[];
  modelProvider: SetupProviderId;
  installed: SampleRecipe["id"][];
  apiKeys: TenantApiKey[];
};

function initialTenants(scenario: OnboardingScenario): SetupTenant[] {
  if (
    [
      "multiple-tenants",
      "new-tenant",
      "creating-new-tenant",
      "tenant-creation-error",
    ].includes(scenario)
  ) {
    return [
      demoTenant,
      { key: "acme-support", name: "Acme Support" },
      { key: "northwind", name: "Northwind" },
    ];
  }
  if (scenario === "renamed-tenant")
    return [{ key: "acme-support", name: "Acme Support" }];
  if (scenario === "new-tenant-setup")
    return [{ key: "customer-care", name: "Customer Care" }];
  return [demoTenant];
}

function tenantDefaults(key: string): TenantProgress {
  return {
    connections:
      key === "acme-support"
        ? [connection("deepgram")]
        : key === "northwind"
          ? [connection("deepgram"), connection("google")]
          : [],
    modelProvider: "google",
    installed: key === "northwind" ? ["voice"] : [],
    apiKeys: [],
  };
}

function initialConnections(scenario: OnboardingScenario): SetupConnection[] {
  if (scenario === "tenant-override")
    return [{ ...connection("telnyx"), telephonyPublicKeyConfigured: true }];
  if (scenario === "tenant-override-error")
    return [{ provider: "deepgram", status: "invalid" }];
  if (scenario === "telnyx-ai-only") return [connection("telnyx")];
  if (scenario === "telnyx-connected")
    return [{ ...connection("telnyx"), telephonyPublicKeyConfigured: true }];
  if (scenario.startsWith("api-key"))
    return [connection("deepgram"), connection("google")];
  if (
    [
      "speech-connected",
      "blocked-samples",
      "validation-error",
      "provider-unavailable",
      "validating",
      "renamed-tenant",
    ].includes(scenario)
  )
    return [connection("deepgram")];
  if (scenario === "multiple-providers")
    return [connection("deepgram"), connection("google"), connection("rime")];
  if (
    [
      "ready-for-samples",
      "samples",
      "loading-samples",
      "sample-error",
      "complete",
    ].includes(scenario)
  )
    return [connection("deepgram"), connection("google")];
  if (scenario === "rime") return [connection("deepgram"), connection("rime")];
  return [];
}

function initialModal(scenario: OnboardingScenario): ServiceModalState | null {
  if (scenario === "service-picker") return { provider: null, status: "idle" };
  if (scenario === "enter-credentials")
    return { provider: "deepgram", status: "idle" };
  if (scenario === "telnyx-credentials" || scenario === "platform-telnyx")
    return { provider: "telnyx", status: "idle" };
  if (scenario === "validating")
    return { provider: "google", status: "submitting" };
  if (scenario === "validation-error")
    return {
      provider: "google",
      status: "error",
      message: "Google rejected this API key. Check the key and try again.",
    };
  if (scenario === "provider-unavailable")
    return {
      provider: "google",
      status: "error",
      message:
        "Google could not be reached. Your saved services are unchanged. Try again.",
    };
  return null;
}

export function OnboardingStory({
  scenario,
  theme,
  publicOrigin = "http://localhost:4000",
}: {
  publicOrigin?: string;
  scenario: OnboardingScenario;
  theme: "dark" | "light";
}) {
  const providers = setupProviders;
  const [page, setPage] = useState<SetupPage>(
    scenario.startsWith("platform-")
      ? "platform"
      : scenario.startsWith("api-key")
        ? "keys"
        : [
              "blocked-samples",
              "samples",
              "loading-samples",
              "sample-error",
              "complete",
            ].includes(scenario)
          ? "samples"
          : [
                "demo-nudge",
                "multiple-tenants",
                "new-tenant",
                "creating-new-tenant",
                "tenant-creation-error",
              ].includes(scenario)
            ? "tenants"
            : "services",
  );
  const [tenants, setTenants] = useState(() => initialTenants(scenario));
  const [tenant, setTenant] = useState<SetupTenant>(
    initialTenants(scenario)[0],
  );
  const [creationStatus, setCreationStatus] =
    useState<TenantCreationStatus | null>(
      scenario === "new-tenant"
        ? "idle"
        : scenario === "creating-new-tenant"
          ? "submitting"
          : scenario === "tenant-creation-error"
            ? "error"
            : null,
    );
  const [tenantConnections, setConnections] = useState(() =>
    initialConnections(scenario),
  );
  const [platformConnections, setPlatformConnections] = useState<
    SetupConnection[]
  >(() =>
    [
      "platform-configured",
      "inherited-services",
      "tenant-override",
      "tenant-override-error",
    ].includes(scenario)
      ? [
          connection("deepgram"),
          connection("google"),
          { ...connection("telnyx"), telephonyPublicKeyConfigured: true },
        ]
      : [],
  );
  const connections = effectiveSetupConnections(
    platformConnections,
    tenantConnections,
  );
  const platformPage = page === "platform";
  const [modal, setModal] = useState(() => initialModal(scenario));
  const [modelProvider, setModelProvider] = useState<SetupProviderId>("google");
  const [selectedRecipe, setSelectedRecipe] = useState<SampleRecipe | null>(
    null,
  );
  const [installed, setInstalled] = useState<SampleRecipe["id"][]>(
    scenario === "complete" ? sampleRecipes.map((recipe) => recipe.id) : [],
  );
  const [sampleError, setSampleError] = useState(
    scenario === "sample-error"
      ? "The call spec could not be prepared. Your services are still connected."
      : undefined,
  );
  const [unavailable, setUnavailable] = useState(scenario === "unavailable");
  const [apiKeys, setApiKeys] = useState<TenantApiKey[]>(
    ["api-key-created", "api-key-existing"].includes(scenario)
      ? [exampleApiKey]
      : [],
  );
  const [keyCreation, setKeyCreation] = useState<ApiKeyCreation>(
    scenario === "api-key-created"
      ? {
          status: "created",
          key: exampleApiKey,
          secret: "storybook-only.demo.example-key.not-a-real-key",
        }
      : {
          status:
            scenario === "api-key-creating"
              ? "submitting"
              : scenario === "api-key-error"
                ? "error"
                : "idle",
        },
  );
  const keyPending = keyCreation.status === "submitting";
  const timerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const [savedTenants, setSavedTenants] = useState<
    Record<string, TenantProgress>
  >({});
  useEffect(() => () => clearTimeout(timerRef.current), []);

  function navigatePage(next: SetupPage) {
    if (keyPending) return;
    setKeyCreation({ status: "idle" });
    setPage(next);
  }

  function createApiKey(name: string, kind: TenantApiKeyKind) {
    if (keyPending) return;
    setKeyCreation({ status: "submitting" });
    timerRef.current = setTimeout(() => {
      const key: TenantApiKey = {
        id: `example-key-${apiKeys.length + 1}`,
        name,
        kind,
      };
      setApiKeys((current) => [...current, key]);
      setKeyCreation({
        status: "created",
        key,
        secret: `storybook-only.${tenant.key}.${key.id}.${kind}.not-a-real-key`,
      });
    }, 650);
  }

  function submitCredential(draft: CredentialDraft) {
    const provider = draft.provider;
    setModal((current) => ({ ...current, provider, status: "submitting" }));
    // Storybook simulates validation; credential values are never retained or sent.
    timerRef.current = setTimeout(() => {
      const updateConnections = platformPage
        ? setPlatformConnections
        : setConnections;
      updateConnections((current) => {
        const previous = current.find((item) => item.provider === provider);
        const next: SetupConnection = {
          ...connection(provider),
          ...(provider === "telnyx"
            ? {
                telephonyPublicKeyConfigured: Boolean(
                  ("publicKey" in draft.values && draft.values.publicKey) ||
                  previous?.telephonyPublicKeyConfigured,
                ),
              }
            : {}),
        };
        return [...current.filter((item) => item.provider !== provider), next];
      });
      if (
        provider === "google" &&
        providersFor("llm", connections, providers).length === 0
      )
        setModelProvider(provider);
      setModal(null);
    }, 650);
  }

  function selectTenant(next: SetupTenant, resume = false) {
    const current = {
      connections: tenantConnections,
      modelProvider,
      installed,
      apiKeys,
    };
    const saved =
      next.key === tenant.key
        ? current
        : (savedTenants[next.key] ?? tenantDefaults(next.key));
    setSavedTenants((previous) => ({ ...previous, [tenant.key]: current }));
    setTenant(next);
    setConnections(saved.connections);
    setModelProvider(saved.modelProvider);
    setInstalled(saved.installed);
    setApiKeys(saved.apiKeys);
    navigatePage(
      resume &&
        voiceSetupReady(
          effectiveSetupConnections(platformConnections, saved.connections),
          providers,
        )
        ? saved.apiKeys.length > 0
          ? "samples"
          : "keys"
        : "services",
    );
  }

  function tryRecipe(recipe: SampleRecipe) {
    if (!recipeCapabilities(recipe, connections, providers)) return;
    setSampleError(undefined);
    setInstalled((current) =>
      current.includes(recipe.id) ? current : [...current, recipe.id],
    );
    setSelectedRecipe(recipe);
  }

  function createTenant(name: string) {
    setCreationStatus("submitting");
    timerRef.current = setTimeout(() => {
      const next: SetupTenant = {
        key: `storybook-tenant-${tenants.length + 1}`,
        name,
      };
      setTenants((current) => [...current, next]);
      selectTenant(next);
      setCreationStatus(null);
    }, 650);
  }

  const overlayOpen =
    modal !== null || selectedRecipe !== null || creationStatus !== null;
  return (
    <AdminShell
      breadcrumbs={
        page === "platform"
          ? [{ label: "Platform" }, { label: "Services" }]
          : page === "tenants"
            ? undefined
            : [
                {
                  label: "Tenants",
                  onSelect: () => navigatePage("tenants"),
                  href: "#/admin",
                },
                { label: tenant.name },
                { label: steps.find((step) => step.page === page)!.label },
              ]
      }
      headerActions={
        <Button
          variant="ghost"
          onClick={() => navigatePage(platformPage ? "tenants" : "platform")}
        >
          {platformPage ? "Tenants" : "Platform services"}
        </Button>
      }
      headerInert={overlayOpen || keyPending}
      theme={theme}
    >
      <main
        aria-hidden={overlayOpen ? "true" : undefined}
        className="tenant-setup"
        inert={overlayOpen ? true : undefined}
      >
        {page !== "tenants" && !platformPage ? (
          <nav aria-label="Tenant setup" className="setup-steps">
            {steps.map((step, index) => (
              <button
                aria-current={page === step.page ? "step" : undefined}
                disabled={keyPending}
                key={step.page}
                onClick={() => navigatePage(step.page)}
              >
                <span>{index + 1}</span>
                {step.label}
              </button>
            ))}
          </nav>
        ) : null}
        {page === "services" || platformPage ? (
          <TenantSetupPage
            connections={platformPage ? platformConnections : connections}
            platform={platformPage}
            platformConnections={platformConnections}
            creating={scenario === "creating-tenant"}
            providers={providers}
            onBrowse={() =>
              setModal({ provider: null, status: "idle" })
            }
            onConnect={(provider) =>
              setModal({ provider, status: "idle" })
            }
            onRemoveCredentials={(provider) => {
              const update = platformPage ? setPlatformConnections : setConnections;
              update((current) => current.filter((item) => item.provider !== provider));
            }}
            onRetry={() => setUnavailable(false)}
            onApiKeys={() => navigatePage("keys")}
            tenant={tenant}
            unavailable={unavailable}
          />
        ) : null}
        {page === "keys" ? (
          <ApiKeysSetupPage
            creation={keyCreation}
            initialKind={scenario === "api-key-full-access" ? "full" : "calls"}
            keys={apiKeys}
            onCallSpecs={() => navigatePage("samples")}
            onCreate={createApiKey}
            tenantName={tenant.name}
          />
        ) : null}
        {page === "samples" ? (
          <SampleRecipesPage
            providers={providers}
            connections={connections}
            error={sampleError}
            installed={installed}
            modelProvider={modelProvider}
            onModelProvider={setModelProvider}
            onServices={() => navigatePage("services")}
            tenantName={tenant.name}
            onTry={tryRecipe}
            preparing={scenario === "loading-samples" ? "voice" : undefined}
          />
        ) : null}
        {page === "tenants" ? (
          <TenantSetupOverview
            providers={providers}
            items={tenants.map((item) => {
              const progress =
                item.key === tenant.key
                  ? { connections: tenantConnections, installed }
                  : (savedTenants[item.key] ?? tenantDefaults(item.key));
              return {
                tenant: item,
                connections: effectiveSetupConnections(
                  platformConnections,
                  progress.connections,
                ),
                hasCallSpecs: progress.installed.length > 0,
              };
            })}
            onOpen={selectTenant}
            onCreate={() => setCreationStatus("idle")}
            onSetup={(next) => selectTenant(next, true)}
          />
        ) : null}
      </main>
      {creationStatus ? (
        <CreateTenantModal
          initialName={
            scenario === "tenant-creation-error" ||
            scenario === "creating-new-tenant"
              ? "Customer Care"
              : undefined
          }
          onClose={() => setCreationStatus(null)}
          onSubmit={createTenant}
          status={creationStatus}
        />
      ) : null}
      {modal ? (
        <ServiceSetupModal
          providers={providers}
          connections={platformPage ? platformConnections : connections}
          platformConnections={platformConnections}
          publicOrigin={publicOrigin}
          scope={
            platformPage
              ? { kind: "platform" }
              : {
                  kind: "tenant",
                  tenantKey: tenant.key,
                  tenantName: tenant.name,
                }
          }
          onOverride={() =>
            setModal((current) =>
              current ? { ...current, overriding: true } : current,
            )
          }
          onUsePlatform={(provider) => {
            setConnections((current) =>
              current.filter((item) => item.provider !== provider),
            );
            setModal(null);
          }}
          onSelect={(provider) =>
            setModal((current) => ({
              ...current,
              provider,
              status: "idle",
              overriding: false,
            }))
          }
          onClose={() => setModal(null)}
          onSubmit={submitCredential}
          onTest={async () => ({ status: "valid" })}
          state={modal}
        />
      ) : null}
      {selectedRecipe ? (
        <SetupDialog
          onClose={() => setSelectedRecipe(null)}
          title={selectedRecipe.title}
        >
          <RecipeDiagram kind={selectedRecipe.id} />
          <p className="recipe-preview-text">
            This recipe is ready for {tenant.name}. Review your services, then
            open the debug console.
          </p>
          <div className="recipe-preview-stack">
            {(
              recipeCapabilities(selectedRecipe, connections, providers) ??
              voiceCapabilities
            ).map((capability) => {
              const provider =
                capability === "llm"
                  ? setupProvider(modelProvider, providers)
                  : providersFor(capability, connections, providers)[0];
              return (
                <div key={capability}>
                  <span>{capabilityLabels[capability]}</span>
                  <strong>
                    {provider?.name} · {provider?.defaultModels[capability]}
                  </strong>
                </div>
              );
            })}
          </div>
          <Button asChild className="setup-primary">
            <a
              href={`/?path=/story/vxpipe-react-workbench--ready-to-start&args=theme:${theme}`}
              rel="noreferrer"
              target="_blank"
            >
              Preview debug console
              <ArrowUpRight aria-hidden="true" size={16} />
            </a>
          </Button>
        </SetupDialog>
      ) : null}
    </AdminShell>
  );
}
