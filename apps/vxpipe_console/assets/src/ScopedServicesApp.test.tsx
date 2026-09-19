import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { App } from "./App";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/admin");
});
const response = (body: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(body), { status }));
const binding = (provider: string, policy = "platform", name = provider) => ({
  provider,
  name,
  policy,
  source: policy === "override" ? "tenant" : "platform",
  status: "connected",
  credential_id: `${provider}-id` as string | null,
  tenant_credential_id: null as string | null,
  platform_available: true,
  saved_fields: ["api_key"],
  last_validated_at: null,
});

test("platform services save, reload and edit the exact persisted binding", async () => {
  window.history.replaceState({}, "", "/admin/platform/services");
  let bindings: ReturnType<typeof binding>[] = [];
  const fetchImpl = vi.fn(
    async (_url: RequestInfo | URL, options?: RequestInit) => {
      if (options?.method === "POST" || options?.method === "PATCH") {
        bindings = [binding("deepgram")];
        return new Response(
          JSON.stringify({ credential: { id: "deepgram-id" } }),
          { status: options.method === "POST" ? 201 : 200 },
        );
      }
      return new Response(JSON.stringify({ tenant: null, bindings }));
    },
  );
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  expect(
    await screen.findByRole("heading", { name: "Platform services" }),
  ).toBeInTheDocument();
  fireEvent.click(
    screen.getAllByRole("button", { name: "Connect a service" })[0],
  );
  fireEvent.change(screen.getByLabelText("Service"), {
    target: { value: "deepgram" },
  });
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-first" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Validate and save" }));
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/platform/credentials",
    expect.objectContaining({
      method: "POST",
      headers: expect.objectContaining({ "x-csrf-token": "csrf-example" }),
      body: JSON.stringify({
        provider: "deepgram",
        name: "deepgram",
        values: { api_key: "synthetic-first" },
      }),
    }),
  );
  fireEvent.click(screen.getByRole("button", { name: "Manage Deepgram" }));
  expect(screen.getByLabelText("API key")).toHaveValue("");
  expect(screen.getByLabelText("API key")).toHaveAttribute(
    "placeholder",
    "••••••••",
  );
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-replacement" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Validate and save" }));
  await waitFor(() =>
    expect(fetchImpl).toHaveBeenCalledWith(
      "/admin/api/platform/credentials/deepgram-id",
      expect.objectContaining({ method: "PATCH" }),
    ),
  );
});

test("tenant setup uses inherited readiness and keeps platform secrets read-only", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/setup-services",
  );
  const fetchImpl = vi.fn(() =>
    response({
      tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example" },
      bindings: [
        binding("google", "inherit"),
        binding("deepgram", "inherit"),
        binding("google", "inherit", "named-model"),
      ],
    }),
  );
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  expect(
    await screen.findByText("Ready for voice samples"),
  ).toBeInTheDocument();
  expect(screen.getAllByText("Inherited from platform")).toHaveLength(2);
  expect(
    screen.getByRole("button", { name: /named-model/ }),
  ).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Manage Deepgram" }));
  const dialog = screen.getByRole("dialog");
  expect(within(dialog).queryByLabelText("API key")).not.toBeInTheDocument();
  expect(
    within(dialog).getByRole("button", { name: "Manage platform services" }),
  ).toBeInTheDocument();
  expect(
    within(dialog).queryByRole("button", { name: "Override for this tenant" }),
  ).toBeInTheDocument();
});

test("tenant override, disable and restore reload durable state without editing the platform row", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/setup-services",
  );
  let service = binding("google", "inherit");
  let saved = false;
  const fetchImpl = vi.fn(
    async (_url: RequestInfo | URL, options?: RequestInit) => {
      if (options?.method === "POST") {
        saved = true;
        service = {
          ...binding("google", "override"),
          credential_id: "tenant-google",
          tenant_credential_id: "tenant-google",
        };
      } else if (options?.method === "PUT") {
        const policy = JSON.parse(String(options.body)).policy;
        service = {
          ...binding("google", policy),
          source: policy === "disabled" ? "tenant" : "platform",
          status: policy === "disabled" ? "disabled" : "connected",
          credential_id: policy === "disabled" ? null : "google-id",
          tenant_credential_id: "tenant-google",
        };
      }
      if (options?.method) return new Response("{}", { status: 200 });
      return new Response(
        JSON.stringify({
          tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example" },
          bindings: [service],
        }),
      );
    },
  );
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  fireEvent.click(
    await screen.findByRole("button", { name: "Manage Google AI Studio" }),
  );
  fireEvent.click(
    screen.getByRole("button", { name: "Override for this tenant" }),
  );
  expect(screen.getByLabelText("API key")).toHaveValue("");
  expect(screen.getByLabelText("API key")).not.toHaveAttribute(
    "placeholder",
    "••••••••",
  );
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-tenant" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Validate and save" }));
  expect(await screen.findByText("Tenant override")).toBeInTheDocument();
  expect(saved).toBe(true);
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/credentials",
    expect.objectContaining({ method: "POST" }),
  );

  fireEvent.click(
    screen.getByRole("button", { name: "Manage Google AI Studio" }),
  );
  fireEvent.click(
    screen.getByRole("button", { name: "Disable for this tenant" }),
  );
  expect(
    await screen.findByText("Disabled for this tenant"),
  ).toBeInTheDocument();
  fireEvent.click(
    screen.getByRole("button", { name: "Manage Google AI Studio" }),
  );
  fireEvent.click(screen.getByRole("button", { name: "Use platform service" }));
  expect(
    await screen.findByText("Inherited from platform"),
  ).toBeInTheDocument();
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/service-policies/google/google",
    expect.objectContaining({
      method: "PUT",
      headers: expect.objectContaining({ "x-csrf-token": "csrf-example" }),
      body: JSON.stringify({ policy: "inherit" }),
    }),
  );
});

test("named overrides replace the dormant tenant row and missing overrides have no saved secret placeholder", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/setup-services",
  );
  const fetchImpl = vi.fn((_url: RequestInfo | URL, options?: RequestInit) =>
    response(
      options?.method
        ? {}
        : {
            tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example" },
            bindings: [
              {
                ...binding("google", "inherit", "named-model"),
                tenant_credential_id: "dormant-tenant",
              },
              {
                ...binding("deepgram", "override"),
                credential_id: null,
                status: "unavailable",
                saved_fields: [],
              },
            ],
          },
    ),
  );
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  fireEvent.click(await screen.findByRole("button", { name: /named-model/ }));
  fireEvent.click(
    screen.getByRole("button", { name: "Override for this tenant" }),
  );
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-named" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Validate and save" }));
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/credentials/dormant-tenant",
    expect.objectContaining({
      method: "PATCH",
      body: JSON.stringify({
        provider: "google",
        name: "named-model",
        values: { api_key: "synthetic-named" },
      }),
    }),
  );
  fireEvent.click(screen.getByRole("button", { name: "Manage Deepgram" }));
  expect(screen.getByLabelText("API key")).not.toHaveAttribute(
    "placeholder",
    "••••••••",
  );
});

test("policy failures stay visible and a successful write with failed reload never pretends to be ready", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/setup-services",
  );
  let attempt = 0;
  const fetchImpl = vi.fn((_url: RequestInfo | URL, options?: RequestInit) => {
    if (options?.method === "PUT")
      return response({}, ++attempt === 1 ? 503 : 200);
    return attempt === 2
      ? response({}, 503)
      : response({
          tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example" },
          bindings: [binding("google", "inherit")],
        });
  });
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  fireEvent.click(
    await screen.findByRole("button", { name: "Manage Google AI Studio" }),
  );
  fireEvent.click(
    screen.getByRole("button", { name: "Disable for this tenant" }),
  );
  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Service settings could not be saved",
  );
  fireEvent.click(
    screen.getByRole("button", { name: "Disable for this tenant" }),
  );
  expect(
    await screen.findByRole("button", { name: "Retry setup" }),
  ).toBeInTheDocument();
  expect(
    screen.getByText(
      "Service settings saved. Retry to load the current state.",
    ),
  ).toBeInTheDocument();
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
});

test("a different platform binding does not turn a tenant-only service into an override", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/setup-services",
  );
  const fetchImpl = vi.fn(() =>
    response({
      tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example" },
      bindings: [
        {
          ...binding("google", "override"),
          platform_available: false,
          tenant_credential_id: "google-id",
        },
        binding("google", "inherit", "another-model"),
      ],
    }),
  );
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  await screen.findByRole("button", { name: "Manage Google AI Studio" });
  expect(screen.queryByText("Tenant override")).not.toBeInTheDocument();
  fireEvent.click(
    screen.getByRole("button", { name: "Manage Google AI Studio" }),
  );
  expect(
    screen.queryByRole("button", { name: "Use platform service" }),
  ).not.toBeInTheDocument();
  expect(
    screen.getByRole("button", { name: "Disable for this tenant" }),
  ).toBeInTheDocument();
});

test("directory outage is retryable and an expired session never looks like empty setup", async () => {
  window.history.replaceState({}, "", "/admin/platform/services");
  const expired = vi.fn();
  const fetchImpl = vi
    .fn()
    .mockImplementationOnce(() => response({}, 503))
    .mockImplementationOnce(() => response({}, 401));
  render(
    <App
      csrfToken="csrf-example"
      fetchImpl={fetchImpl}
      onSessionExpired={expired}
    />,
  );
  fireEvent.click(await screen.findByRole("button", { name: "Retry setup" }));
  await waitFor(() => expect(expired).toHaveBeenCalledTimes(1));
  expect(
    screen.queryByRole("button", { name: "Connect a service" }),
  ).not.toBeInTheDocument();
});
