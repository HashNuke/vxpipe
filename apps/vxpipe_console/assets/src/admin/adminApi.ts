import type { TenantSummary } from "./tenantTypes";

export type TenantDirectoryPage = {
  tenants: TenantSummary[];
  pagination: {
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  };
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

function expectedPageLength(page: number, pageSize: number, total: number) {
  if (total === 0) return 0;
  return Math.min(pageSize, total - (page - 1) * pageSize);
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
