export type TenantApiKeyKind = "calls" | "full";
export type TenantApiKey = { id: string; name: string; kind: TenantApiKeyKind };
export type ApiKeyCreation =
  | { status: "idle" | "submitting" | "error" }
  | { status: "created"; key: TenantApiKey; secret: string };

// Administration.authenticate checks each grant independently: admin does not imply calls.
export const tenantApiKeyKinds = [
  {
    id: "calls" as const,
    label: "Create & Join Calls",
    description:
      "Create calls, issue participant join tokens, and read call details.",
    scopes: ["calls"],
  },
  {
    id: "full" as const,
    label: "Full Access",
    description: "Access all operations for this tenant.",
    scopes: ["admin", "calls"],
  },
];

export function tenantApiKeyKind(kind: TenantApiKeyKind) {
  return tenantApiKeyKinds.find((option) => option.id === kind)!;
}
