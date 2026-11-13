import type { SetupConnection, SetupServiceScope } from "./setupCatalog";
import { validWebhookUrl } from "./serviceBindingsApi";
import { parseTelephonyApplications, type TelephonyApplication } from "./telephonyApplicationsApi";

export type TelnyxConnection = {
  platformApplicationId: string | null;
  credential: SetupConnection | null;
  platformAvailable: boolean;
  applications: TelephonyApplication[];
  webhookUrls: { platform: string; tenant: string | null };
};
const record = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
const applicationId = (value: unknown): value is string | null => value === null || typeof value === "string" && /^[\x21-\x7e]{1,128}$/.test(value);

export function parseTelnyxConnection(value: unknown, scope: SetupServiceScope): TelnyxConnection {
  const invalid = () => new Error("Telnyx settings could not be loaded. Try again.");
  if (!record(value) || !applicationId(value.platform_application_id) || !record(value.webhook_urls) ||
      !validWebhookUrl(value.webhook_urls.platform) ||
      !(scope.kind === "platform" ? value.webhook_urls.tenant === null : validWebhookUrl(value.webhook_urls.tenant))) throw invalid();
  const tenant = scope.kind === "tenant" ? scope.tenantKey : "platform";
  const { applications } = parseTelephonyApplications({ tenant: { key: tenant }, applications: value.applications, truncated: false }, tenant);
  const credential = value.credential;
  if (credential !== null && (!record(credential) || credential.provider !== "telnyx" || credential.name !== "telnyx" ||
      !["platform", "tenant"].includes(String(credential.source)) ||
      !["connected", "invalid", "unavailable"].includes(String(credential.status)) ||
      typeof credential.platform_available !== "boolean" || !Array.isArray(credential.saved_fields) ||
      !credential.saved_fields.every(field => field === "api_key" || field === "public_key"))) throw invalid();
  const saved = credential as { source: "platform" | "tenant"; status: SetupConnection["status"]; platform_available: boolean; saved_fields: string[] } | null;
  return {
    platformApplicationId: value.platform_application_id,
    applications,
    credential: saved ? { provider: "telnyx", source: saved.source, status: saved.status,
      telephonyPublicKeyConfigured: saved.saved_fields.includes("public_key"),
      savedFields: saved.saved_fields.map(field => field === "api_key" ? "apiKey" : "publicKey") } : null,
    platformAvailable: saved?.platform_available ?? false,
    webhookUrls: value.webhook_urls as TelnyxConnection["webhookUrls"],
  };
}

export function telnyxSaveError(status: number, body: unknown): string {
  const code = record(body) && record(body.error) ? body.error.code : null;
  if (status === 403) return "Your role cannot change these settings.";
  if (code === "phone_number_in_use") return "A phone number is already assigned on the shared application. Change its routing first.";
  if (code === "telephony_service_conflict") return "This application is already in use. Enter a separate application ID.";
  if (code === "telnyx_application_required") return "Enter a tenant application ID with these credentials.";
  if (code === "invalid_provider_auth") return "Check the API key and public key, then try again.";
  return "Telnyx settings could not be saved. Check the connection and try again.";
}
