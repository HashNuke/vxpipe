import { expect, test } from "vitest";

import {
  parseCallPage,
  parseCreatedCredential,
  parseDefinitionPage,
  parseServiceDirectory,
  parseTenantPage,
} from "./adminApi";

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
      tenants: [
        { key: "AAAAAAAAAAAAAAAA", name: 42, created_at: "not-a-date" },
      ],
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
    expect(() => parseTenantPage(response)).toThrow(
      "Invalid tenant directory response",
    );
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

test("validates and maps a filtered tenant call page", () => {
  expect(
    parseCallPage({
      tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
      definitions: [
        { id: "delivery-rescheduling", name: "Delivery rescheduling" },
      ],
      definitions_truncated: false,
      selected_definition_id: "delivery-rescheduling",
      calls: [
        {
          id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
          definition_id: "delivery-rescheduling",
          definition_name: "Delivery rescheduling",
          definition_revision: 3,
          state: "ongoing",
          created_at: "2026-09-17T02:20:00Z",
        },
      ],
      pagination: { page: 2, page_size: 25, total: 26, total_pages: 2 },
    }),
  ).toEqual({
    tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
    definitions: [
      { id: "delivery-rescheduling", name: "Delivery rescheduling" },
    ],
    definitionsTruncated: false,
    selectedDefinitionId: "delivery-rescheduling",
    calls: [
      {
        id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
        definitionId: "delivery-rescheduling",
        definitionName: "Delivery rescheduling",
        definitionRevision: 3,
        state: "ongoing",
        createdAt: "2026-09-17T02:20:00Z",
      },
    ],
    pagination: { page: 2, pageSize: 25, total: 26, totalPages: 2 },
  });
});

test("rejects malformed calls, unknown selected definitions, and contradictory call pages", () => {
  const base = {
    tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
    definitions: [
      { id: "delivery-rescheduling", name: "Delivery rescheduling" },
    ],
    definitions_truncated: false,
    selected_definition_id: "delivery-rescheduling",
    calls: [],
    pagination: { page: 1, page_size: 25, total: 0, total_pages: 0 },
  };

  expect(() =>
    parseCallPage({ ...base, selected_definition_id: "missing-definition" }),
  ).toThrow("Invalid call directory response");

  expect(() =>
    parseCallPage({
      ...base,
      calls: [{ id: "call", state: "invented" }],
      pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
    }),
  ).toThrow("Invalid call directory response");

  expect(() =>
    parseCallPage({
      ...base,
      pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
    }),
  ).toThrow("Invalid call directory response");

  expect(() =>
    parseCallPage({
      ...base,
      calls: [
        {
          id: "call",
          definition_id: "other-definition",
          definition_name: "Other definition",
          definition_revision: 1,
          state: "ended",
          created_at: "2026-09-17T02:20:00Z",
        },
      ],
      pagination: { page: 1, page_size: 25, total: 1, total_pages: 1 },
    }),
  ).toThrow("Invalid call directory response");

  expect(() =>
    parseCallPage({ ...base, definitions_truncated: "yes" }),
  ).toThrow("Invalid call directory response");
});

test("validates and projects metadata-only service inventory", () => {
  expect(
    parseServiceDirectory({
      tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
      truncated: false,
      credentials: [
        {
          id: "credential-google",
          provider: "google",
          name: "primary",
          auth_kind: "api_key",
          status: "active",
          credential_preview: [
            { label: "API key", format: "last_four", last_four: "8c4a" },
          ],
          last_validated_at: "2026-09-17T01:55:00Z",
          created_at: "2026-09-17T02:00:00Z",
          updated_at: "2026-09-17T02:00:00Z",
        },
        {
          id: "credential-telnyx",
          provider: "telnyx",
          name: "voice",
          auth_kind: "api_key",
          status: "active",
          credential_preview: [
            { label: "API key", format: "last_four", last_four: "7f2b" },
          ],
          last_validated_at: null,
          created_at: "2026-09-17T02:01:00Z",
          updated_at: "2026-09-17T02:01:00Z",
        },
      ],
      telephony_services: [
        {
          id: "service-support",
          name: "support",
          provider: "telnyx",
          provider_connection_id: "connection-primary",
          credential_id: "credential-telnyx",
          outbound_number: "+14155550100",
        },
      ],
    }),
  ).toEqual({
    tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
    truncated: false,
    services: [
      {
        id: "credential-google",
        credentialId: "credential-google",
        name: "Google AI Studio",
        provider: "google",
        credentialName: "primary",
        credentialPreview: [
          { label: "API key", format: "last_four", lastFour: "8c4a" },
        ],
        lastValidatedAt: "2026-09-17T01:55:00Z",
        updatedAt: "2026-09-17T02:00:00Z",
      },
      {
        id: "credential-telnyx",
        credentialId: "credential-telnyx",
        name: "Telnyx",
        provider: "telnyx",
        credentialName: "voice",
        credentialPreview: [
          { label: "API key", format: "last_four", lastFour: "7f2b" },
        ],
        lastValidatedAt: null,
        updatedAt: "2026-09-17T02:01:00Z",
      },
    ],
  });
});

test("keeps credential update time when inventory is partial", () => {
  const result = parseServiceDirectory({
    tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
    truncated: true,
    credentials: [
      {
        id: "credential-telnyx",
        provider: "telnyx",
        name: "voice",
        auth_kind: "api_key",
        status: "active",
        credential_preview: [{ label: "API key", format: "masked" }],
        last_validated_at: "2026-09-17T01:55:00Z",
        created_at: "2026-09-17T02:01:00Z",
        updated_at: "2026-09-17T02:01:00Z",
      },
    ],
    telephony_services: [],
  });

  expect(result.services[0]?.updatedAt).toBe("2026-09-17T02:01:00Z");
});

test("rejects service responses containing malformed, cross-linked, or secret data", () => {
  const valid = {
    tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example tenant" },
    truncated: false,
    credentials: [
      {
        id: "credential-google",
        provider: "google",
        name: "primary",
        auth_kind: "api_key",
        status: "active",
        created_at: "2026-09-17T02:00:00Z",
        updated_at: "2026-09-17T02:00:00Z",
      },
    ],
    telephony_services: [],
  };

  expect(() =>
    parseServiceDirectory({
      ...valid,
      credentials: [{ ...valid.credentials[0], api_key: "must-not-render" }],
    }),
  ).toThrow("Invalid service directory response");

  expect(() =>
    parseServiceDirectory({
      ...valid,
      telephony_services: [
        {
          id: "service-support",
          name: "support",
          provider: "telnyx",
          provider_connection_id: "connection-primary",
          credential_id: "missing-credential",
          outbound_number: null,
        },
      ],
    }),
  ).toThrow("Invalid service directory response");
});

test("maps a created credential response without accepting private response fields", () => {
  const response = {
    credential: {
      id: "credential-deepgram",
      provider: "deepgram",
      name: "realtime",
      auth_kind: "api_key",
      status: "active",
      credential_preview: [
        { label: "API key", format: "last_four", last_four: "8c4a" },
      ],
      last_validated_at: "2026-09-17T01:55:00Z",
      created_at: "2026-09-17T02:00:00Z",
      updated_at: "2026-09-17T02:00:00Z",
    },
  };

  expect(parseCreatedCredential(response)).toEqual({
    id: "credential-deepgram",
    credentialId: "credential-deepgram",
    name: "Deepgram",
    provider: "deepgram",
    credentialName: "realtime",
    credentialPreview: [
      { label: "API key", format: "last_four", lastFour: "8c4a" },
    ],
    lastValidatedAt: "2026-09-17T01:55:00Z",
    updatedAt: "2026-09-17T02:00:00Z",
  });

  expect(() =>
    parseCreatedCredential({
      credential: { ...response.credential, api_key: "must-not-render" },
    }),
  ).toThrow("Invalid credential response");
});
