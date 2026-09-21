import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { TenantTelephonyApplications } from "./admin/TenantTelephonyApplications";
import type { ServiceBinding } from "./admin/serviceBindingsApi";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/admin");
});
const tenant = { key: "AAAAAAAAAAAAAAAA", name: "Phone example" };
const prefix = `/admin/api/tenants/${tenant.key}/telephony-applications`;
const application = {
  id: "5eef6e68-11aa-434a-9a99-abc123def456",
  name: "support",
  provider_connection_id: "synthetic-application",
  outbound_number: null as string | null,
  published_routes: [] as Array<Record<string, unknown>>,
};
const binding: ServiceBinding = {
  provider: "telnyx",
  name: "telnyx",
  source: "platform",
  status: "connected",
  credentialId: "synthetic-credential",
  platformAvailable: true,
  savedFields: ["apiKey", "publicKey"],
  telephonyPublicKeyConfigured: true,
  lastValidatedAt: null,
};
const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status });
function mount(
  fetchImpl: typeof fetch,
  selectedBinding = binding,
  onConnectionDetails = vi.fn(),
) {
  return render(
    <TenantTelephonyApplications
      binding={selectedBinding}
      credentialsLoaded
      csrfToken="synthetic-csrf"
      fetchImpl={fetchImpl}
      onConnectionDetails={onConnectionDetails}
      onSessionExpired={vi.fn()}
      tenantKey={tenant.key}
      webhookUrl="https://callbacks.example.test/webhooks/platform/telnyx"
    />,
  );
}
function fillApplication() {
  fireEvent.change(screen.getByLabelText("Service name"), {
    target: { value: "support" },
  });
  fireEvent.change(screen.getByLabelText("Voice API application ID"), {
    target: { value: "synthetic-application" },
  });
}

test("operator creates and edits a tenant application then reloads its durable metadata", async () => {
  let applications: (typeof application)[] = [];
  const fetchImpl = vi.fn(
    async (_url: RequestInfo | URL, init?: RequestInit) => {
      if (init?.method === "POST" || init?.method === "PATCH") {
        applications = [{ ...application, ...JSON.parse(String(init.body)) }];
        return response(
          { application: applications[0] },
          init.method === "POST" ? 201 : 200,
        );
      }
      return response({ tenant, applications, truncated: false });
    },
  );
  const view = mount(fetchImpl);
  fireEvent.click(
    await screen.findByRole("button", { name: "Add application" }),
  );
  fillApplication();
  fireEvent.click(screen.getByRole("button", { name: "Save application" }));
  await screen.findByText("Application saved.");
  await waitFor(() =>
    expect(
      screen.getByRole("heading", { name: "Phone routing" }),
    ).toHaveFocus(),
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    prefix,
    expect.objectContaining({
      method: "POST",
      credentials: "same-origin",
      headers: expect.objectContaining({ "x-csrf-token": "synthetic-csrf" }),
      body: JSON.stringify({
        name: "support",
        provider_connection_id: "synthetic-application",
        outbound_number: null,
      }),
    }),
  );
  fireEvent.click(screen.getByRole("button", { name: "Edit support" }));
  expect(screen.getByLabelText("Service name")).toHaveAttribute("readonly");
  fireEvent.change(screen.getByLabelText("Voice API application ID"), {
    target: { value: "replacement-application" },
  });
  fireEvent.change(screen.getByLabelText("Outbound caller number (optional)"), {
    target: { value: "+15550002000" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save application" }));
  await waitFor(() =>
    expect(fetchImpl).toHaveBeenCalledWith(
      `${prefix}/${application.id}`,
      expect.objectContaining({
        method: "PATCH",
        body: JSON.stringify({
          provider_connection_id: "replacement-application",
          outbound_number: "+15550002000",
        }),
      }),
    ),
  );
  await screen.findByText("replacement-application");
  view.unmount();
  mount(fetchImpl);
  await screen.findByText("replacement-application");
  expect(screen.getByText(/No published numbers/)).toBeInTheDocument();
});

test("published progress shows revision, ambiguity and bounded results without claiming live readiness", async () => {
  const route = {
    number: "+15550001000",
    call_spec_id: "phone-spec",
    call_spec_name: "Phone support",
    call_spec_revision: 2,
    participant_ref: "caller",
    ambiguous: true,
  };
  const fetchImpl = vi.fn(async () =>
    response({
      tenant,
      applications: [{ ...application, published_routes: [route] }],
      truncated: true,
    }),
  );
  mount(fetchImpl);
  const section = await screen.findByRole("region", { name: "Phone routing" });
  expect(await within(section).findByText("+15550001000")).toBeInTheDocument();
  expect(
    within(section).getByText(/Phone support.*revision 2/),
  ).toBeInTheDocument();
  expect(
    within(section).getByText(/Multiple published routes/),
  ).toBeInTheDocument();
  expect(
    within(section).getByText(
      /Showing the first 100 applications or 500 routes/,
    ),
  ).toBeInTheDocument();
  expect(
    within(section).getByText(
      /A successful live call still needs to be verified/,
    ),
  ).toBeInTheDocument();
});

test("load and save failures preserve the form, and a committed save is never offered for resubmission", async () => {
  let loadFails = true;
  let conflict = true;
  let saved = false;
  const fetchImpl = vi.fn(
    async (_url: RequestInfo | URL, init?: RequestInit) => {
      if (init?.method === "POST") {
        if (conflict)
          return response(
            { error: { code: "telephony_service_conflict" } },
            409,
          );
        saved = true;
        loadFails = true;
        return response({ application }, 201);
      }
      return loadFails
        ? response({}, 503)
        : response({
            tenant,
            applications: saved ? [application] : [],
            truncated: false,
          });
    },
  );
  mount(fetchImpl);
  await screen.findByRole("button", { name: "Retry phone routing" });
  loadFails = false;
  fireEvent.click(
    await screen.findByRole("button", { name: "Retry phone routing" }),
  );
  fireEvent.click(
    await screen.findByRole("button", { name: "Add application" }),
  );
  fillApplication();
  fireEvent.click(screen.getByRole("button", { name: "Save application" }));
  await screen.findByText(
    /That service name or application ID is already used/,
  );
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue(
    "synthetic-application",
  );
  conflict = false;
  fireEvent.click(screen.getByRole("button", { name: "Save application" }));
  await screen.findByText(/Application saved. Retry to load/);
  expect(
    screen.queryByRole("button", { name: "Save application" }),
  ).not.toBeInTheDocument();
  loadFails = false;
  fireEvent.click(screen.getByRole("button", { name: "Retry phone routing" }));
  await screen.findByText("synthetic-application");
  expect(
    fetchImpl.mock.calls.filter(([, init]) => init?.method === "POST"),
  ).toHaveLength(2);
  loadFails = true;
  fireEvent.click(screen.getByRole("button", { name: "Reload phone routing" }));
  await screen.findByText(
    "Phone routing could not be loaded. Your saved applications are safe.",
  );
});

test("an API-only tenant override cannot borrow platform phone readiness", async () => {
  const fetchImpl = vi.fn(async () =>
    response({ tenant, applications: [application], truncated: false }),
  );
  const onConnectionDetails = vi.fn();
  mount(
    fetchImpl,
    {
      ...binding,
      source: "tenant",
      savedFields: ["apiKey"],
      telephonyPublicKeyConfigured: false,
    },
    onConnectionDetails,
  );
  await screen.findByText(
    /Add a public key to this tenant’s Telnyx connection/,
  );
  expect(
    screen.getByRole("button", { name: "Add application" }),
  ).toBeDisabled();
  expect(await screen.findByText("synthetic-application")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Connection details" }));
  expect(onConnectionDetails).toHaveBeenCalledOnce();
});
