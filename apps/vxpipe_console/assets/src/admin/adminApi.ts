import type { TenantSummary } from "./tenantTypes";
import type { DefinitionSummary, TenantContext } from "./definitionTypes";

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

function invalidResponse() {
  return new Error("Invalid tenant directory response");
}

function invalidDefinitionResponse() {
  return new Error("Invalid definition directory response");
}
