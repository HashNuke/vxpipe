import catalog from "./setupCatalog.json";
import type { SetupConnection, SetupServiceScope } from "./setupCatalog";

export type ServiceBinding = SetupConnection & {
  name: string;
  policy: "platform" | "inherit" | "override" | "disabled";
  credentialId: string | null;
  tenantCredentialId: string | null;
  platformAvailable: boolean;
};
export type BindingDirectory = {
  tenant: { key: string; name: string } | null;
  bindings: ServiceBinding[];
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
        ? item.policy === "platform"
        : ["inherit", "override", "disabled"].includes(String(item.policy))) ||
      item.source !==
        (["platform", "inherit"].includes(String(item.policy))
          ? "platform"
          : "tenant") ||
      !["connected", "invalid", "unavailable", "disabled"].includes(
        String(item.status),
      ) ||
      !optionalId(item.credential_id) ||
      !optionalId(item.tenant_credential_id) ||
      (item.status === "connected" && item.credential_id === null) ||
      (item.policy === "disabled" &&
        (item.status !== "disabled" || item.credential_id !== null)) ||
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
      policy: item.policy as ServiceBinding["policy"],
      source: item.source as ServiceBinding["source"],
      status: item.status as ServiceBinding["status"],
      credentialId: item.credential_id as string | null,
      tenantCredentialId: item.tenant_credential_id as string | null,
      platformAvailable: item.platform_available,
      telephonyPublicKeyConfigured: item.saved_fields.includes("public_key"),
      savedFields: item.saved_fields.map(
        (field) => credentialFields[field as keyof typeof credentialFields],
      ),
    };
  });
  return { tenant: tenant as BindingDirectory["tenant"], bindings };
}
