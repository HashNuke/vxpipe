import { parseModelCatalog, type ModelCatalog } from "./modelCatalog";
import catalog from "./setupCatalog.json";
import type { ProviderCapabilities, SetupConnection, SetupServiceScope } from "./setupCatalog";

export type ServiceBinding = SetupConnection & {
  name: string;
  credentialId: string | null;
  platformAvailable: boolean;
  lastValidatedAt: string | null;
};
export type BindingDirectory = {
  tenant: { key: string; name: string } | null;
  bindings: ServiceBinding[];
  providerCapabilities: ProviderCapabilities;
  modelCatalog: ModelCatalog;
  webhookUrls?: { platform: string; tenant: string | null };
};

const record = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const optionalId = (value: unknown) =>
  value === null ||
  (typeof value === "string" && value.length > 0 && value.length <= 128);
const credentialFields = {
  api_key: "apiKey",
  public_key: "publicKey",
  account_sid: "accountSid",
  auth_token: "authToken",
} as const;
const invalid = () =>
  new Error(
    "Service setup could not be loaded. Retry to load the saved services.",
  );

export function parseBindingDirectory(
  value: unknown,
  scope: SetupServiceScope,
): BindingDirectory {
  if (
    !record(value) ||
    !Array.isArray(value.bindings) ||
    !record(value.provider_capabilities) ||
    Object.keys(value.provider_capabilities).length > 32 ||
    !Object.values(value.provider_capabilities).every(
      (capabilities) =>
        Array.isArray(capabilities) &&
        capabilities.length <= 16 &&
        capabilities.every((capability) => typeof capability === "string"),
    ) ||
    value.bindings.length > 1500
  )
    throw invalid();
  const tenant = value.tenant;
  if (
    scope.kind === "platform"
      ? tenant !== null
      : !record(tenant) ||
        tenant.key !== scope.tenantKey ||
        typeof tenant.name !== "string"
  )
    throw invalid();
  const names = new Set<string>();
  const bindings = value.bindings.map((item): ServiceBinding => {
    if (
      !record(item) ||
      !catalog.providers.some((provider) => provider.id === item.provider) ||
      typeof item.name !== "string" ||
      !/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(item.name) ||
      !(scope.kind === "platform"
        ? item.source === "platform"
        : ["platform", "tenant"].includes(String(item.source))) ||
      !["connected", "invalid", "unavailable"].includes(String(item.status)) ||
      !optionalId(item.credential_id) ||
      (item.status === "connected" && item.credential_id === null) ||
      typeof item.platform_available !== "boolean" ||
      !Array.isArray(item.saved_fields) ||
      !item.saved_fields.every((field) =>
        Object.keys(credentialFields).includes(field),
      ) ||
      !(
        item.last_validated_at === null ||
        (typeof item.last_validated_at === "string" &&
          !Number.isNaN(Date.parse(item.last_validated_at)))
      )
    )
      throw invalid();
    const key = `${item.provider}:${item.name}`;
    if (names.has(key)) throw invalid();
    names.add(key);
    return {
      provider: item.provider as ServiceBinding["provider"],
      name: item.name,
      source: item.source as ServiceBinding["source"],
      status: item.status as ServiceBinding["status"],
      credentialId: item.credential_id as string | null,
      platformAvailable: item.platform_available,
      lastValidatedAt: item.last_validated_at as string | null,
      telephonyPublicKeyConfigured: item.saved_fields.includes("public_key"),
      savedFields: item.saved_fields.map(
        (field) => credentialFields[field as keyof typeof credentialFields],
      ),
    };
  });
  let webhookUrls: BindingDirectory["webhookUrls"];
  if (value.webhook_urls !== undefined) {
    const urls = value.webhook_urls;
    if (
      !record(urls) ||
      !validWebhookUrl(urls.platform) ||
      (scope.kind === "platform"
        ? urls.tenant !== null
        : !validWebhookUrl(urls.tenant))
    )
      throw invalid();
    webhookUrls = {
      platform: urls.platform as string,
      tenant: urls.tenant as string | null,
    };
  }
  return {
    tenant: tenant as BindingDirectory["tenant"],
    bindings,
    providerCapabilities: value.provider_capabilities as ProviderCapabilities,
    modelCatalog: parseModelCatalog(value.model_catalog),
    webhookUrls,
  };
}

function validWebhookUrl(value: unknown): value is string {
  if (typeof value !== "string" || value.length > 2304) return false;
  try {
    const url = new URL(value);
    return (
      ["http:", "https:"].includes(url.protocol) &&
      !url.username &&
      !url.password &&
      !url.search &&
      !url.hash
    );
  } catch {
    return false;
  }
}
