import type { TenantSummary } from "./tenantTypes";
import type { DefinitionSummary, TenantContext } from "./definitionTypes";
import type { CallSummary, DefinitionContext } from "./callTypes";

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
  calls: CallSummary[];
  pagination: TenantDirectoryPage["pagination"];
};

export function parseTenantPage(value: unknown): TenantDirectoryPage {
  if (!isRecord(value) || !Array.isArray(value.tenants) || !isRecord(value.pagination)) {
    throw invalidResponse();
  }

  const tenants = value.tenants.map(parseTenant);
  const { page, page_size: pageSize, total, total_pages: totalPages } = value.pagination;

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
  const { page, page_size: pageSize, total, total_pages: totalPages } = value.pagination;

  if (
    !validPagination(page, pageSize, total, totalPages, definitions.length)
  ) {
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

  const { page, page_size: pageSize, total, total_pages: totalPages } = value.pagination;

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

function parseCallDefinition(value: unknown): Pick<DefinitionContext, "id" | "name"> {
  if (
    !isRecord(value) ||
    typeof value.id !== "string" ||
    value.id.length === 0 ||
    !(value.name === null || (typeof value.name === "string" && value.name.length > 0))
  ) {
    throw invalidCallResponse();
  }

  return { id: value.id, name: value.name };
}

function parseCall(value: unknown): CallSummary {
  if (
    !isRecord(value) ||
    typeof value.id !== "string" ||
    value.id.length === 0 ||
    typeof value.definition_id !== "string" ||
    value.definition_id.length === 0 ||
    !(value.definition_name === null ||
      (typeof value.definition_name === "string" && value.definition_name.length > 0)) ||
    !isPositiveInteger(value.definition_revision) ||
    !member(value.state, ["prepared", "admitting", "running", "ended", "failed"]) ||
    !validTimestamp(value.created_at) ||
    !validOptionalTimestamp(value.started_at) ||
    !validOptionalTimestamp(value.ended_at) ||
    !(
      value.terminal_reason === null ||
      (typeof value.terminal_reason === "string" && value.terminal_reason.length > 0)
    ) ||
    !member(value.archive_state, ["complete", "incomplete", "unconfirmed"])
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
    startedAt: value.started_at,
    endedAt: value.ended_at,
    terminalReason: value.terminal_reason,
    archiveState: value.archive_state,
  };
}

function parseDefinition(value: unknown): DefinitionSummary {
  if (
    !isRecord(value) ||
    typeof value.id !== "string" ||
    value.id.length === 0 ||
    !(value.name === null || (typeof value.name === "string" && value.name.length > 0)) ||
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

function isPositiveInteger(value: unknown): value is number {
  return Number.isInteger(value) && Number(value) > 0;
}

function isNonNegativeInteger(value: unknown): value is number {
  return Number.isInteger(value) && Number(value) >= 0;
}

function validTimestamp(value: unknown): value is string {
  return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

function validOptionalTimestamp(value: unknown): value is string | null {
  return value === null || validTimestamp(value);
}

function member<T extends string>(value: unknown, values: readonly T[]): value is T {
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
