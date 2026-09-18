import type { SetupServiceScope } from "./setupCatalog";

// Called by Storybook's Node config with only the public application settings.
// Production UI will receive this origin from the backend runtime configuration.
export function setupPublicOrigin(settings: {
  APP_HOST?: string;
  PORT?: string;
  VXPIPE_DEV_TLS?: string;
}): string {
  const host = settings.APP_HOST?.trim().replace(/\.$/, "") || "localhost";
  const port = settings.PORT?.trim() || "4000";
  const local = ["localhost", "127.0.0.1", "::1", "[::1]"].includes(host);
  const directTls = settings.VXPIPE_DEV_TLS === "phoenix";
  const directHttp = settings.VXPIPE_DEV_TLS === "http";
  const scheme = directTls || (!local && !directHttp) ? "https" : "http";
  const authority =
    host.includes(":") && !host.startsWith("[") ? `[${host}]` : host;
  const includePort = local || directTls || directHttp;
  return new URL(`${scheme}://${authority}${includePort ? `:${port}` : ""}`)
    .origin;
}

export function telnyxWebhookUrl(
  origin: string,
  scope: SetupServiceScope,
): string {
  const path =
    scope.kind === "platform"
      ? "/webhooks/platform/telnyx"
      : `/webhooks/tenants/${encodeURIComponent(scope.tenantKey)}/telnyx`;
  return new URL(path, origin).href;
}
