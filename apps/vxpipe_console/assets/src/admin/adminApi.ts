import type { TenantSummary } from "./tenantTypes";
import type { DefinitionSummary, TenantContext } from "./definitionTypes";
import type { CallDirectoryItem, DefinitionContext } from "./callTypes";
import type {
  CredentialPreview,
  ServiceInventoryItem,
  ServiceProvider,
} from "./serviceTypes";

export type TenantDirectoryPage = {
  tenants: TenantSummary[];
  pagination: {
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  };
};

export type DefinitionDirectoryPage = {
  tenant: TenantContext;
  definitions: DefinitionSummary[];
  pagination: TenantDirectoryPage["pagination"];
};

export type CallDirectoryPage = {
  tenant: TenantContext;
  definitions: Array<Pick<DefinitionContext, "id" | "name">>;
  definitionsTruncated: boolean;
  selectedDefinitionId: string | null;
  calls: CallDirectoryItem[];
  pagination: TenantDirectoryPage["pagination"];
};

export type ServiceDirectory = {
  tenant: TenantContext;
  services: ServiceInventoryItem[];
  truncated: boolean;
};

export function parseTenantPage(value: unknown): TenantDirectoryPage {
  if (
    !isRecord(value) ||
    !Array.isArray(value.tenants) ||
    !isRecord(value.pagination)
  ) {
    throw invalidResponse();
  }

  const tenants = value.tenants.map(parseTenant);
  const {
    page,
    page_size: pageSize,
    total,
    total_pages: totalPages,
  } = value.pagination;

  if (
    !isPositiveInteger(page) ||
    !isPositiveInteger(pageSize) ||
    !isNonNegativeInteger(total) ||
    !isNonNegativeInteger(totalPages) ||
    totalPages !== Math.ceil(total / pageSize) ||
    page > Math.max(totalPages, 1) ||
    tenants.length !== expectedPageLength(page, pageSize, total)
  ) {
    throw invalidResponse();
  }

  return { tenants, pagination: { page, pageSize, total, totalPages } };
}

export function parseDefinitionPage(value: unknown): DefinitionDirectoryPage {
  if (
    !isRecord(value) ||
    !isRecord(value.tenant) ||
    !Array.isArray(value.definitions) ||
    !isRecord(value.pagination) ||
    typeof value.tenant.key !== "string" ||
    value.tenant.key.length === 0 ||
    typeof value.tenant.name !== "string" ||
    value.tenant.name.length === 0
  ) {
    throw invalidDefinitionResponse();
  }

  const definitions = value.definitions.map(parseDefinition);
  const {
    page,
    page_size: pageSize,
    total,
    total_pages: totalPages,
  } = value.pagination;

  if (!validPagination(page, pageSize, total, totalPages, definitions.length)) {
    throw invalidDefinitionResponse();
  }

  return {
    tenant: { key: value.tenant.key, name: value.tenant.name },
    definitions,
    pagination: {
      page: Number(page),
      pageSize: Number(pageSize),
      total: Number(total),
      totalPages: Number(totalPages),
    },
  };
}

export function parseCallPage(value: unknown): CallDirectoryPage {
  if (
    !isRecord(value) ||
    !isRecord(value.tenant) ||
    !Array.isArray(value.definitions) ||
    !Array.isArray(value.calls) ||
    !isRecord(value.pagination) ||
    typeof value.definitions_truncated !== "boolean" ||
    typeof value.tenant.key !== "string" ||
    value.tenant.key.length === 0 ||
    typeof value.tenant.name !== "string" ||
    value.tenant.name.length === 0
  ) {
    throw invalidCallResponse();
  }

  const definitions = value.definitions.map(parseCallDefinition);
  const selectedDefinitionId = value.selected_definition_id;

  if (
    !(
      selectedDefinitionId === null ||
      (typeof selectedDefinitionId === "string" &&
        selectedDefinitionId.length > 0 &&
        definitions.some(({ id }) => id === selectedDefinitionId))
    )
  ) {
    throw invalidCallResponse();
  }

  const calls = value.calls.map(parseCall);

  if (
    selectedDefinitionId !== null &&
    calls.some(({ definitionId }) => definitionId !== selectedDefinitionId)
  ) {
    throw invalidCallResponse();
  }

  const {
    page,
    page_size: pageSize,
    total,
    total_pages: totalPages,
  } = value.pagination;

  if (!validPagination(page, pageSize, total, totalPages, calls.length)) {
    throw invalidCallResponse();
  }

  return {
    tenant: { key: value.tenant.key, name: value.tenant.name },
    definitions,
    definitionsTruncated: value.definitions_truncated,
    selectedDefinitionId,
    calls,
    pagination: {
      page: Number(page),
      pageSize: Number(pageSize),
      total: Number(total),
      totalPages: Number(totalPages),
    },
  };
}

export function parseServiceDirectory(value: unknown): ServiceDirectory {
  if (
    !isRecord(value) ||
    !exactKeys(value, [
      "tenant",
      "credentials",
      "telephony_services",
      "truncated",
    ]) ||
    !isRecord(value.tenant) ||
    !exactKeys(value.tenant, ["key", "name"]) ||
    typeof value.tenant.key !== "string" ||
    value.tenant.key.length === 0 ||
    typeof value.tenant.name !== "string" ||
    value.tenant.name.length === 0 ||
    !Array.isArray(value.credentials) ||
    !Array.isArray(value.telephony_services) ||
    typeof value.truncated !== "boolean"
  ) {
    throw invalidServiceResponse();
  }

  const truncated = value.truncated;
  const credentials = value.credentials.map(parseCredentialMetadata);
  const telephonyServices = value.telephony_services.map(
    parseTelephonyMetadata,
  );
  const credentialsById = new Map(
    credentials.map((credential) => [credential.id, credential]),
  );

  if (
    new Set(credentials.map(({ id }) => id)).size !== credentials.length ||
    new Set(telephonyServices.map(({ id }) => id)).size !==
      telephonyServices.length ||
    telephonyServices.some((service) => {
      const credential = credentialsById.get(service.credentialId);
      return !credential || credential.provider !== service.provider;
    })
  ) {
    throw invalidServiceResponse();
  }

  const services = credentials
    .filter(({ status }) => status === "active")
    .map(credentialInventory);

  return {
    tenant: { key: value.tenant.key, name: value.tenant.name },
    services,
    truncated,
  };
}

export function parseCreatedCredential(value: unknown): ServiceInventoryItem {
  if (!isRecord(value) || !exactKeys(value, ["credential"])) {
    throw invalidCredentialResponse();
  }

  let credential: CredentialMetadata;
  try {
    credential = parseCredentialMetadata(value.credential);
  } catch {
    throw invalidCredentialResponse();
  }
  if (credential.status !== "active") throw invalidCredentialResponse();
  return credentialInventory(credential);
}

type CredentialMetadata = {
  id: string;
  provider: ServiceProvider;
  name: string;
  updatedAt: string;
  authKind: "api_key" | "account_sid_auth_token";
  status: "active" | "revoked";
  credentialPreview: CredentialPreview[];
};

type TelephonyMetadata = {
  id: string;
  name: string;
  provider: "telnyx" | "twilio";
  providerConnectionId: string;
  credentialId: string;
  outboundNumber: string | null;
};

function parseCredentialMetadata(value: unknown): CredentialMetadata {
  if (
    !isRecord(value) ||
    !exactKeys(value, [
      "id",
      "provider",
      "name",
      "auth_kind",
      "status",
      "credential_preview",
      "created_at",
      "updated_at",
    ]) ||
    typeof value.id !== "string" ||
    value.id.length === 0 ||
    !member(value.provider, [
      "google",
      "vertex_ai",
      "zenmux",
      "deepgram",
      "telnyx",
      "twilio",
    ]) ||
    typeof value.name !== "string" ||
    value.name.length === 0 ||
    !member(value.status, ["active", "revoked"]) ||
    !Array.isArray(value.credential_preview) ||
    !validTimestamp(value.created_at) ||
    !validTimestamp(value.updated_at) ||
    !(
      (value.provider === "twilio" &&
        value.auth_kind === "account_sid_auth_token") ||
      (value.provider !== "twilio" && value.auth_kind === "api_key")
    )
  ) {
    throw invalidServiceResponse();
  }

  return {
    id: value.id,
    provider: value.provider,
    name: value.name,
    updatedAt: value.updated_at,
    authKind: value.auth_kind,
    status: value.status,
    credentialPreview: value.credential_preview.map(parseCredentialPreview),
  };
}

function parseCredentialPreview(value: unknown): CredentialPreview {
  if (
    !isRecord(value) ||
    typeof value.label !== "string" ||
    value.label.length === 0 ||
    !member(value.format, ["last_four", "masked"])
  ) {
    throw invalidServiceResponse();
  }

  if (value.format === "masked" && exactKeys(value, ["label", "format"])) {
    return { label: value.label, format: "masked" };
  }

  if (
    value.format === "last_four" &&
    exactKeys(value, ["label", "format", "last_four"]) &&
    typeof value.last_four === "string" &&
    value.last_four.length === 4
  ) {
    return {
      label: value.label,
      format: "last_four",
      lastFour: value.last_four,
    };
  }

  throw invalidServiceResponse();
}

function parseTelephonyMetadata(value: unknown): TelephonyMetadata {
  if (
    !isRecord(value) ||
    !exactKeys(value, [
      "id",
      "name",
      "provider",
      "provider_connection_id",
      "credential_id",
      "outbound_number",
    ]) ||
    typeof value.id !== "string" ||
    value.id.length === 0 ||
    typeof value.name !== "string" ||
    value.name.length === 0 ||
    !member(value.provider, ["telnyx", "twilio"]) ||
    typeof value.provider_connection_id !== "string" ||
    value.provider_connection_id.length === 0 ||
    typeof value.credential_id !== "string" ||
    value.credential_id.length === 0 ||
    !(
      value.outbound_number === null ||
      typeof value.outbound_number === "string"
    )
  ) {
    throw invalidServiceResponse();
  }

  return {
    id: value.id,
    name: value.name,
    provider: value.provider,
    providerConnectionId: value.provider_connection_id,
    credentialId: value.credential_id,
    outboundNumber: value.outbound_number,
  };
}

function credentialInventory(
  credential: CredentialMetadata,
): ServiceInventoryItem {
  return {
    id: credential.id,
    credentialId: credential.id,
    name: providerLabel(credential.provider),
    provider: credential.provider,
    credentialName: credential.name,
    credentialPreview: credential.credentialPreview,
    updatedAt: credential.updatedAt,
  };
}

function providerLabel(provider: ServiceProvider) {
  return {
    google: "Google AI Studio",
    vertex_ai: "Google Vertex AI",
    zenmux: "Zenmux",
    deepgram: "Deepgram",
    telnyx: "Telnyx",
    twilio: "Twilio",
  }[provider];
}

function parseCallDefinition(
  value: unknown,
): Pick<DefinitionContext, "id" | "name"> {
  if (
    !isRecord(value) ||
    typeof value.id !== "string" ||
    value.id.length === 0 ||
    !(
      value.name === null ||
      (typeof value.name === "string" && value.name.length > 0)
    )
  ) {
    throw invalidCallResponse();
  }

  return { id: value.id, name: value.name };
}

function parseCall(value: unknown): CallDirectoryItem {
  if (
    !isRecord(value) ||
    !exactKeys(value, [
      "id",
      "definition_id",
      "definition_name",
      "definition_revision",
      "state",
      "created_at",
    ]) ||
    typeof value.id !== "string" ||
    value.id.length === 0 ||
    typeof value.definition_id !== "string" ||
    value.definition_id.length === 0 ||
    !(
      value.definition_name === null ||
      (typeof value.definition_name === "string" &&
        value.definition_name.length > 0)
    ) ||
    !isPositiveInteger(value.definition_revision) ||
    !member(value.state, ["ongoing", "ended"]) ||
    !validTimestamp(value.created_at)
  ) {
    throw invalidCallResponse();
  }

  return {
    id: value.id,
    definitionId: value.definition_id,
    definitionName: value.definition_name,
    definitionRevision: value.definition_revision,
    state: value.state,
    createdAt: value.created_at,
  };
}

function parseDefinition(value: unknown): DefinitionSummary {
  if (
    !isRecord(value) ||
    typeof value.id !== "string" ||
    value.id.length === 0 ||
    !(
      value.name === null ||
      (typeof value.name === "string" && value.name.length > 0)
    ) ||
    !isPositiveInteger(value.latest_revision) ||
    !(
      value.published_revision === null ||
      (isPositiveInteger(value.published_revision) &&
        value.published_revision <= value.latest_revision)
    ) ||
    !isNonNegativeInteger(value.call_count) ||
    typeof value.updated_at !== "string" ||
    Number.isNaN(Date.parse(value.updated_at))
  ) {
    throw invalidDefinitionResponse();
  }

  return {
    id: value.id,
    name: value.name,
    latestRevision: value.latest_revision,
    publishedRevision: value.published_revision,
    callCount: value.call_count,
    updatedAt: value.updated_at,
  };
}

function expectedPageLength(page: number, pageSize: number, total: number) {
  if (total === 0) return 0;
  return Math.min(pageSize, total - (page - 1) * pageSize);
}

function validPagination(
  page: unknown,
  pageSize: unknown,
  total: unknown,
  totalPages: unknown,
  itemCount: number,
) {
  return (
    isPositiveInteger(page) &&
    isPositiveInteger(pageSize) &&
    isNonNegativeInteger(total) &&
    isNonNegativeInteger(totalPages) &&
    totalPages === Math.ceil(total / pageSize) &&
    page <= Math.max(totalPages, 1) &&
    itemCount === expectedPageLength(page, pageSize, total)
  );
}

function parseTenant(value: unknown): TenantSummary {
  if (
    !isRecord(value) ||
    typeof value.key !== "string" ||
    value.key.length === 0 ||
    typeof value.name !== "string" ||
    value.name.length === 0 ||
    typeof value.created_at !== "string" ||
    Number.isNaN(Date.parse(value.created_at))
  ) {
    throw invalidResponse();
  }

  return { key: value.key, name: value.name, createdAt: value.created_at };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function exactKeys(value: Record<string, unknown>, expected: string[]) {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  return (
    actual.length === sortedExpected.length &&
    actual.every((key, index) => key === sortedExpected[index])
  );
}

function isPositiveInteger(value: unknown): value is number {
  return Number.isInteger(value) && Number(value) > 0;
}

function isNonNegativeInteger(value: unknown): value is number {
  return Number.isInteger(value) && Number(value) >= 0;
}

function validTimestamp(value: unknown): value is string {
  return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

function member<T extends string>(
  value: unknown,
  values: readonly T[],
): value is T {
  return typeof value === "string" && values.includes(value as T);
}

function invalidResponse() {
  return new Error("Invalid tenant directory response");
}

function invalidDefinitionResponse() {
  return new Error("Invalid definition directory response");
}

function invalidCallResponse() {
  return new Error("Invalid call directory response");
}

function invalidServiceResponse() {
  return new Error("Invalid service directory response");
}

function invalidCredentialResponse() {
  return new Error("Invalid credential response");
}
