import { expect, test } from "vitest";

import { parseTenantPage } from "./adminApi";

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
