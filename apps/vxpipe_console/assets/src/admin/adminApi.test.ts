import { expect, test } from "vitest";

import { parseDefinitionPage, parseTenantPage } from "./adminApi";

test("validates and maps the tenant directory response", () => {
  expect(
    parseTenantPage({
      tenants: [
        {
          key: "AAAAAAAAAAAAAAAA",
          name: "Example tenant",
          created_at: "2026-09-17T01:00:00Z",
        },
      ],
      pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
    }),
  ).toEqual({
    tenants: [
      {
        key: "AAAAAAAAAAAAAAAA",
        name: "Example tenant",
        createdAt: "2026-09-17T01:00:00Z",
      },
    ],
    pagination: { page: 1, pageSize: 25, total: 1, totalPages: 1 },
  });
});

test("rejects malformed tenant data instead of rendering a partial response", () => {
  expect(() =>
    parseTenantPage({
      tenants: [{ key: "AAAAAAAAAAAAAAAA", name: 42, created_at: "not-a-date" }],
      pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
    }),
  ).toThrow("Invalid tenant directory response");
});

test("rejects pagination metadata that contradicts the returned page", () => {
  for (const response of [
    {
      tenants: [],
      pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
    },
    {
      tenants: [],
      pagination: { page: 1, page_size: 25, total: 0, total_pages: 1 },
    },
    {
      tenants: [],
      pagination: { page: 2, page_size: 25, total: 0, total_pages: 0 },
    },
    {
      tenants: [
        {
          key: "AAAAAAAAAAAAAAAA",
          name: "Only one tenant",
          created_at: "2026-09-17T01:00:00Z",
        },
      ],
      pagination: { page: 1, page_size: 25, total: 30, total_pages: 2 },
    },
  ]) {
    expect(() => parseTenantPage(response)).toThrow("Invalid tenant directory response");
  }
});

test("validates and maps a tenant definition page", () => {
  expect(
    parseDefinitionPage({
      tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
      definitions: [
        {
          id: "delivery-rescheduling",
          name: "Delivery rescheduling",
          latest_revision: 4,
          published_revision: 3,
          call_count: 5,
          updated_at: "2026-09-17T03:00:00Z",
        },
      ],
      pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
    }),
  ).toEqual({
    tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
    definitions: [
      {
        id: "delivery-rescheduling",
        name: "Delivery rescheduling",
        latestRevision: 4,
        publishedRevision: 3,
        callCount: 5,
        updatedAt: "2026-09-17T03:00:00Z",
      },
    ],
    pagination: { page: 1, pageSize: 25, total: 1, totalPages: 1 },
  });
});

test("rejects malformed definition summaries and contradictory definition pages", () => {
  expect(() =>
    parseDefinitionPage({
      tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
      definitions: [],
      pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
    }),
  ).toThrow("Invalid definition directory response");

  expect(() =>
    parseDefinitionPage({
      tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
      definitions: [
        {
          id: "delivery-rescheduling",
          name: "Delivery rescheduling",
          latest_revision: 3,
          published_revision: 4,
          call_count: 5,
          updated_at: "not-a-date",
        },
      ],
      pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
    }),
  ).toThrow("Invalid definition directory response");
});
