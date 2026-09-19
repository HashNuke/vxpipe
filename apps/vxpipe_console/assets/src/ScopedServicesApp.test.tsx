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
const binding = (provider: string, source = "platform", name = provider) => ({
  provider,
  name,
  source,
  status: "connected",
  credential_id: `${provider}-id` as string | null,
  platform_available: true,
  saved_fields: ["api_key"],
  last_validated_at: null,
});

test("Telnyx saves the public key and shows backend URLs and saved-field metadata", async () => {
  window.history.replaceState({}, "", "/admin/platform/services");
  let saved = false;
  const fetchImpl = vi.fn(
    async (_url: RequestInfo | URL, options?: RequestInit) => {
      if (options?.method === "POST") {
        saved = true;
        return new Response("{}", { status: 201 });
      }
      return new Response(
        JSON.stringify({
          tenant: null,
          bindings: saved
            ? [
                {
                  ...binding("telnyx"),
                  saved_fields: ["api_key", "public_key"],
                },
              ]
            : [],
          webhook_urls: {
            platform:
              "https://callbacks.example.test/voice/webhooks/platform/telnyx",
            tenant: null,
          },
        }),
      );
    },
  );
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  await screen.findByRole("heading", { name: "Platform services" });
  fireEvent.click(
    screen.getAllByRole("button", { name: "Connect a service" })[0],
  );
  fireEvent.change(screen.getByLabelText("Service"), {
    target: { value: "telnyx" },
  });
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "https://callbacks.example.test/voice/webhooks/platform/telnyx",
  );
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-api-key" },
  });
  const publicKey = "AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  fireEvent.change(screen.getByLabelText("Public key"), {
    target: { value: publicKey },
  });
  fireEvent.click(screen.getByRole("button", { name: "Validate and save" }));
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/platform/credentials",
    expect.objectContaining({
      body: JSON.stringify({
        provider: "telnyx",
        name: "telnyx",
        values: { api_key: "synthetic-api-key", public_key: publicKey },
      }),
    }),
  );
  fireEvent.click(screen.getAllByRole("button", { name: "Manage Telnyx" })[0]);
  expect(screen.getByLabelText("Public key")).toHaveValue("");
  expect(screen.getByLabelText("Public key")).toHaveAttribute(
    "placeholder",
    "••••••••",
  );
  expect(
    screen.getByText(/Leave blank to remove the saved public key/),
  ).toBeInTheDocument();
});

test("Telnyx overrides switch URL scope without borrowing the inherited public key", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/setup-services",
  );
  const fetchImpl = vi.fn(() =>
    response({
      tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example" },
      bindings: [
        { ...binding("telnyx"), saved_fields: ["api_key", "public_key"] },
      ],
      webhook_urls: {
        platform: "http://localhost:4567/webhooks/platform/telnyx",
        tenant:
          "http://localhost:4567/webhooks/tenants/AAAAAAAAAAAAAAAA/telnyx",
      },
    }),
  );
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  fireEvent.click(
    (await screen.findAllByRole("button", { name: "Manage Telnyx" }))[0],
  );
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "http://localhost:4567/webhooks/platform/telnyx",
  );
  expect(screen.queryByLabelText("Public key")).not.toBeInTheDocument();
  expect(screen.getByText(/Local preview/)).toBeInTheDocument();
  fireEvent.click(
    screen.getByRole("button", { name: "Override for this tenant" }),
  );
  expect(screen.getByLabelText("Webhook URL")).toHaveValue(
    "http://localhost:4567/webhooks/tenants/AAAAAAAAAAAAAAAA/telnyx",
  );
  expect(screen.getByLabelText("Public key")).not.toHaveAttribute(
    "placeholder",
  );
  expect(
    screen.getByText(/Update your Telnyx Voice API application/),
  ).toBeInTheDocument();
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
      if (options?.method === "DELETE") {
        bindings = [];
        return new Response(null, { status: 204 });
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
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  fireEvent.click(screen.getByRole("button", { name: "Manage Deepgram" }));
  expect(
    screen.queryByRole("button", { name: /Disable/ }),
  ).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Remove service" }));
  await waitFor(() =>
    expect(
      screen.queryByRole("button", { name: "Manage Deepgram" }),
    ).not.toBeInTheDocument(),
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/platform/credentials/deepgram-id",
    expect.objectContaining({ method: "DELETE" }),
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
        binding("google", "platform"),
        binding("deepgram", "platform"),
        binding("google", "platform", "named-model"),
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

test("tenant credential removal restores inheritance and there is no disable control", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/setup-services",
  );
  let service = binding("google");
  const fetchImpl = vi.fn(
    async (_url: RequestInfo | URL, options?: RequestInit) => {
      if (options?.method === "POST") {
        service = {
          ...binding("google", "tenant"),
          credential_id: "tenant-google",
        };
        return new Response("{}", { status: 201 });
      }
      if (options?.method === "DELETE") {
        service = binding("google");
        return new Response(null, { status: 204 });
      }
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
  expect(
    screen.queryByRole("button", { name: /Disable/ }),
  ).not.toBeInTheDocument();
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
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/credentials",
    expect.objectContaining({ method: "POST" }),
  );
  fireEvent.click(
    screen.getByRole("button", { name: "Manage Google AI Studio" }),
  );
  expect(
    screen.queryByRole("button", { name: /Disable/ }),
  ).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Use platform service" }));
  expect(
    await screen.findByText("Inherited from platform"),
  ).toBeInTheDocument();
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/credentials/tenant-google",
    expect.objectContaining({
      method: "DELETE",
      headers: expect.objectContaining({ "x-csrf-token": "csrf-example" }),
    }),
  );
});

test("a named inherited service creates a new tenant credential without touching the platform row", async () => {
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
            bindings: [binding("google", "platform", "named-model")],
          },
    ),
  );
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  fireEvent.click(await screen.findByRole("button", { name: /named-model/ }));
  fireEvent.click(
    screen.getByRole("button", { name: "Override for this tenant" }),
  );
  expect(screen.getByLabelText("API key")).not.toHaveAttribute(
    "placeholder",
    "••••••••",
  );
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-named" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Validate and save" }));
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/tenants/AAAAAAAAAAAAAAAA/credentials",
    expect.objectContaining({
      method: "POST",
      body: JSON.stringify({
        provider: "google",
        name: "named-model",
        values: { api_key: "synthetic-named" },
      }),
    }),
  );
});

test("removal failures stay visible and a successful write with failed reload never pretends to be ready", async () => {
  window.history.replaceState(
    {},
    "",
    "/admin/tenants/AAAAAAAAAAAAAAAA/setup-services",
  );
  let attempt = 0;
  const fetchImpl = vi.fn((_url: RequestInfo | URL, options?: RequestInit) => {
    if (options?.method === "DELETE")
      return response({}, ++attempt === 1 ? 503 : 200);
    return attempt === 2
      ? response({}, 503)
      : response({
          tenant: { key: "AAAAAAAAAAAAAAAA", name: "Example" },
          bindings: [binding("google", "tenant")],
        });
  });
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  fireEvent.click(
    await screen.findByRole("button", { name: "Manage Google AI Studio" }),
  );
  fireEvent.click(screen.getByRole("button", { name: "Use platform service" }));
  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Service could not be removed",
  );
  fireEvent.click(screen.getByRole("button", { name: "Use platform service" }));
  expect(
    await screen.findByRole("button", { name: "Retry setup" }),
  ).toBeInTheDocument();
  expect(
    screen.getByText("Service removed. Retry to load the current state."),
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
          ...binding("google", "tenant"),
          platform_available: false,
        },
        binding("google", "platform", "another-model"),
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
    screen.getByRole("button", { name: "Remove service" }),
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
