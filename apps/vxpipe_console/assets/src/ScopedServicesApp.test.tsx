import { setupProviders } from "./admin/setupCatalog";
import { modelCatalogFixture } from "./admin/modelCatalogFixtures";
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { App } from "./test/ResourceApp";
import { ScopedServicesApp } from "./ScopedServicesApp";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/admin");
});
const response = (body: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(body), { status }));
const withInventory = (fetchImpl: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>, canEdit = true) =>
  async (input: RequestInfo | URL, init?: RequestInit) => {
    if (!String(input).includes("/integrations?")) return fetchImpl(input, init);
    const result = await fetchImpl("/api/platform/services", init);
    if (!result.ok) return result;
    const directory = await result.json();
    const connections = directory.bindings.map((value: ReturnType<typeof binding>) => ({ ...value, can_edit: canEdit }));
    const connectedOnly = String(input).includes("category=connected");
    return Response.json({ tenant: null, installation_version: "0.1.0", directory_status: "local", connections,
      page: null, fallback_items: [], local_items: setupProviders.filter(provider =>
        directory.provider_capabilities[provider.id]?.includes("credential") && (!connectedOnly || connections.some((value: ReturnType<typeof binding>) => value.provider === provider.id))
      ).map(provider => ({ id: `provider-${provider.id}`, kind: "provider", name: provider.name,
        connection: { provider_id: provider.id }, can_connect: canEdit,
        connections: connections.filter((value: ReturnType<typeof binding>) => value.provider === provider.id) })) });
  };
const withAdminSession = (fetchImpl: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>) => {
  const inventory = withInventory(fetchImpl);
  return (input: RequestInfo | URL, init?: RequestInit) => String(input) === "/admin/api/session"
    ? response({ user: { id: "owner", email: "owner@example.test", roleId: "admin", enabled: true, memberships: [] },
        role: { id: "admin", name: "Admin", description: "", kind: "admin", grants: [] } })
    : inventory(input, init);
};
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
const providerCapabilities = {
  deepgram: ["credential", "stt", "tts"],
  google: ["credential", "llm"],
  rime: ["credential", "tts"],
  telnyx: ["credential", "telephony"],
  twilio: ["credential", "telephony"],
  zenmux: ["credential", "llm"],
};

test("editing immediately opens a loading dialog and Cancel ignores a late settings response", async () => {
  let resolve!: (response: Response) => void;
  const fetchImpl = vi.fn<(input: RequestInfo | URL, init?: RequestInit) => Promise<Response>>(() => new Promise<Response>(done => { resolve = done; }));
  render(<ScopedServicesApp scope={{ kind: "platform" }} csrfToken="csrf" fetchImpl={fetchImpl}
    onNavigate={vi.fn()} showTelephonyApplications={false}
    renderInventory={({ onManage }) => <button onClick={() => onManage("google")}>Edit Google</button>} />);
  const edit = screen.getByRole("button", { name: "Edit Google" });
  edit.focus();
  fireEvent.click(edit);
  expect(within(screen.getByRole("dialog")).getByRole("status")).toHaveTextContent("Loading integration settings");
  expect(edit.closest("main")).toHaveAttribute("inert");
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(fetchImpl.mock.calls[0][1]?.signal?.aborted).toBe(true);
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  await act(async () => resolve(Response.json({ tenant: null, bindings: [], model_catalog: modelCatalogFixture, provider_capabilities: providerCapabilities })));
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  await waitFor(() => expect(edit).toHaveFocus());
});

test("loading hands over to the credential editor and restores the original Edit button", async () => {
  let resolve!: (response: Response) => void;
  const fetchImpl = vi.fn(() => new Promise<Response>(done => { resolve = done; }));
  render(<ScopedServicesApp scope={{ kind: "platform" }} csrfToken="csrf" fetchImpl={fetchImpl}
    onNavigate={vi.fn()} showTelephonyApplications={false}
    renderInventory={({ onManage }) => <button onClick={() => onManage("google")}>Edit Google</button>} />);
  const edit = screen.getByRole("button", { name: "Edit Google" });
  edit.focus();
  fireEvent.click(edit);
  expect(screen.getByRole("dialog")).toBeVisible();
  await act(async () => resolve(Response.json({ tenant: null, bindings: [], model_catalog: modelCatalogFixture, provider_capabilities: providerCapabilities })));
  expect(await screen.findByLabelText("API key")).toBeVisible();
  expect(screen.queryByText("Loading integration settings…")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  await waitFor(() => expect(edit).toHaveFocus());
});

test("integration inventory opens the existing provider credential workflow", async () => {
  const fetchImpl = vi.fn(async () => response({ tenant: null, bindings: [],
    model_catalog: modelCatalogFixture, provider_capabilities: providerCapabilities }));
  render(<ScopedServicesApp scope={{ kind: "platform" }} csrfToken="csrf" fetchImpl={fetchImpl}
    onNavigate={vi.fn()} renderInventory={({ onManage }) => <button onClick={() => onManage("google")}>Connect Google integration</button>} />);
  fireEvent.click(await screen.findByRole("button", { name: "Connect Google integration" }));
  expect(await screen.findByLabelText(/API key/i)).toBeVisible();
  expect(screen.getByRole("dialog")).toBeVisible();
  expect(screen.queryByRole("button", { name: "Connect a service" })).not.toBeInTheDocument();
});

test("platform displays existing Telnyx and Deepgram once without writing credentials", async () => {
  window.history.replaceState({}, "", "/platform/services/ai");
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, options?: RequestInit) => {
    if (options?.method && options.method !== "GET") throw new Error("unexpected credential write");
    return response({
          tenant: null,
          bindings: [
            { ...binding("telnyx"), platform_available: false },
            { ...binding("deepgram"), platform_available: false },
          ],
          model_catalog: modelCatalogFixture, provider_capabilities: providerCapabilities,
        });
  });

  render(<App csrfToken="csrf-example" fetchImpl={withAdminSession(fetchImpl)} />);
  expect(await screen.findByRole("article", { name: "Telnyx" })).toBeVisible();
  expect(screen.getAllByRole("article", { name: "Telnyx" })).toHaveLength(1);
  expect(screen.getAllByRole("article", { name: "Deepgram" })).toHaveLength(1);
  expect(screen.queryByRole("button", { name: "Connect a service" })).not.toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "AI providers" })).not.toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "Telephony" })).not.toBeInTheDocument();
  expect(fetchImpl.mock.calls.every(([, options]) => !options?.method || options.method === "GET")).toBe(true);
});

test("platform service reader sees connections without mutation controls", async () => {
  window.history.replaceState({}, "", "/platform/services/ai");
  const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
    if (String(input) === "/admin/api/session") return response({
      user: { id: "reader", email: "reader@example.test", roleId: "reader", enabled: true, memberships: [] },
      role: { id: "reader", name: "Platform reader", description: "", kind: null,
        grants: [{ permission: "platform_services.read", scope: "installation" }] },
    });
    return response({
      tenant: null,
      bindings: [binding("deepgram")],
      model_catalog: modelCatalogFixture,
      provider_capabilities: providerCapabilities,
    });
  });

  render(<App csrfToken="csrf-example" fetchImpl={withInventory(fetchImpl, false)} />);
  expect(await screen.findByRole("article", { name: "Deepgram" })).toBeVisible();
  expect(screen.queryByRole("button", { name: "Connect a service" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: /Manage Deepgram|More actions for Deepgram/ })).not.toBeInTheDocument();
});

test("a chosen service stays fixed in its editor with only working capability badges", async () => {
  window.history.replaceState({}, "", "/platform/services/ai");
  const fetchImpl = vi.fn(async () => response({
    tenant: null, bindings: [], model_catalog: modelCatalogFixture,
    provider_capabilities: providerCapabilities,
  }));
  render(<App csrfToken="csrf-example" fetchImpl={withAdminSession(fetchImpl)} />);
  fireEvent.click(await screen.findByRole("button", { name: "Connect Google AI Studio" }));
  await screen.findByLabelText(/API key/i);
  const dialog = screen.getByRole("dialog", { name: "Google AI Studio" });
  expect(within(dialog).queryByRole("combobox", { name: "Service" })).not.toBeInTheDocument();
  expect(dialog).not.toHaveTextContent("Binding:");
  expect(dialog).toHaveTextContent("LLM");
  expect(dialog).not.toHaveTextContent("Speech-to-text");
  expect(dialog).not.toHaveTextContent("Text-to-speech");
  expect(dialog).not.toHaveTextContent("Speech-to-speech");
  fireEvent.keyDown(dialog, { key: "Escape" });

  fireEvent.click(await screen.findByRole("button", { name: "Connect Rime" }));
  await screen.findByLabelText(/API key/i);
  const rime = screen.getByRole("dialog", { name: "Rime" });
  expect(rime).not.toHaveTextContent("Credentials only");
  expect(rime).toHaveTextContent("Text-to-speech");
});

test("Telnyx saves the public key and shows backend URLs and saved-field metadata", async () => {
  window.history.replaceState({}, "", "/platform/services/ai");
  let saved = false;
  const fetchImpl = vi.fn(
    async (_url: RequestInfo | URL, options?: RequestInit) => {
      if (String(_url).endsWith("/credentials/test")) return Response.json({ status: "valid" });
      if (options?.method === "PATCH") {
        saved = true;
        return Response.json({});
      }
      if (String(_url).endsWith("/telnyx-connection")) return Response.json({
        platform_application_id: saved ? "platform-app" : null,
        applications: [], credential: saved ? { ...binding("telnyx"), saved_fields: ["api_key", "public_key"] } : null,
        webhook_urls: { platform: "https://callbacks.example.test/voice/webhooks/platform/telnyx", tenant: null },
      });
      return new Response(
        JSON.stringify({
          tenant: null,
          model_catalog: modelCatalogFixture, provider_capabilities: providerCapabilities,
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
  render(<App csrfToken="csrf-example" fetchImpl={withAdminSession(fetchImpl)} />);
  await screen.findByRole("heading", { name: "Platform Integrations" });
  fireEvent.click(await screen.findByRole("button", { name: "Connect Telnyx" }));
  await screen.findByLabelText("API key");
  expect(await screen.findByLabelText("Webhook URL")).toHaveValue(
    "https://callbacks.example.test/voice/webhooks/platform/telnyx",
  );
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-api-key" },
  });
  const publicKey = "AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  fireEvent.change(screen.getByLabelText("Public key"), {
    target: { value: publicKey },
  });
  fireEvent.click(screen.getByRole("button", { name: "Test credentials" }));
  expect(await screen.findByText("Credentials tested successfully.")).toBeVisible();
  expect(saved).toBe(false);
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "platform-app" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(screen.getByRole("status", { name: "Notification" })).toHaveTextContent("Telnyx connection saved.");
  expect(screen.getByRole("status", { name: "Notification" })).toHaveClass("fixed");
  expect(fetchImpl).toHaveBeenCalledWith(
    "/api/platform/telnyx-connection",
    expect.objectContaining({
      body: JSON.stringify({
        application_id: "platform-app",
        credentials: { api_key: "synthetic-api-key", public_key: publicKey },
      }),
    }),
  );
  fireEvent.click(await screen.findByRole("button", { name: "Edit Telnyx" }));
  fireEvent.click(await screen.findByRole("button", { name: "Edit credentials" }));
  expect(screen.getByLabelText("Public key")).toHaveValue("");
  expect(screen.getByLabelText("Public key")).toHaveAttribute(
    "placeholder",
    "Leave blank to keep saved public key",
  );
  expect(screen.queryByText(/Leave blank to remove/)).not.toBeInTheDocument();
});

test("platform services test and save separately, then edit the exact persisted binding", async () => {
  window.history.replaceState({}, "", "/platform/services/ai");
  let bindings: ReturnType<typeof binding>[] = [];
  const fetchImpl = vi.fn(
    async (_url: RequestInfo | URL, options?: RequestInit) => {
      if (String(_url).endsWith("/credentials/test")) {
        return new Response(JSON.stringify({ status: "valid" }));
      }
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
      return new Response(JSON.stringify({ tenant: null, bindings, model_catalog: modelCatalogFixture, provider_capabilities: providerCapabilities }));
    },
  );
  render(<App csrfToken="csrf-example" fetchImpl={withAdminSession(fetchImpl)} />);
  expect(
    await screen.findByRole("heading", { name: "Platform Integrations" }),
  ).toBeInTheDocument();
  fireEvent.click(await screen.findByRole("button", { name: "Connect Deepgram" }));
  await screen.findByLabelText("API key");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-first" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Test credentials" }));
  expect(await screen.findByText("Credentials tested successfully.")).toBeVisible();
  expect(await screen.findByRole("dialog")).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith(
    "/api/platform/credentials/test",
    expect.objectContaining({
      method: "POST",
      body: JSON.stringify({
        provider: "deepgram",
        name: "deepgram",
        values: { api_key: "synthetic-first" },
      }),
    }),
  );
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/api/platform/credentials",
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
  fireEvent.click(await screen.findByRole("button", { name: "Edit Deepgram" }));
  expect(await screen.findByLabelText("API key")).toHaveValue("");
  expect(screen.getByLabelText("API key")).toHaveAttribute(
    "placeholder",
    "••••••••",
  );
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-replacement" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  await waitFor(() =>
    expect(fetchImpl).toHaveBeenCalledWith(
      "/api/platform/credentials/deepgram-id",
      expect.objectContaining({ method: "PATCH" }),
    ),
  );
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  fireEvent.click(await screen.findByRole("button", { name: "Edit Deepgram" }));
  expect(
    screen.queryByRole("button", { name: /Disable/ }),
  ).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Remove credentials" })).not.toBeInTheDocument();
  await screen.findByLabelText("API key");
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
  fireEvent.click(await screen.findByRole("button", { name: "Remove Deepgram (deepgram) credentials" }));
  await waitFor(() =>
    expect(
      screen.queryByRole("button", { name: "Edit Deepgram" }),
    ).not.toBeInTheDocument(),
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/api/platform/credentials/deepgram-id",
    expect.objectContaining({ method: "DELETE" }),
  );
});

test("failed card removal keeps the credentials visible and reports the error", async () => {
  window.history.replaceState({}, "", "/platform/services/ai");
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, options?: RequestInit) =>
    options?.method === "DELETE"
      ? response({ error: { code: "in_use" } }, 409)
      : response({
          tenant: null,
          bindings: [binding("deepgram")],
          model_catalog: modelCatalogFixture, provider_capabilities: providerCapabilities,
        }),
  );

  render(<App csrfToken="csrf-example" fetchImpl={withAdminSession(fetchImpl)} />);
  fireEvent.click(await screen.findByRole("button", { name: "Remove Deepgram (deepgram) credentials" }));

  expect(await screen.findByRole("alert", { name: "Notification" })).toHaveTextContent(
    /credential is used by a telephony service/,
  );
  expect(screen.getByRole("article", { name: "Deepgram" })).toBeVisible();
});

test("platform save failure appears in a page notification while the form stays open", async () => {
  window.history.replaceState({}, "", "/platform/services/ai");
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, options?: RequestInit) =>
    options?.method === "POST"
      ? response({ error: { code: "unavailable" } }, 503)
      : response({ tenant: null, bindings: [], model_catalog: modelCatalogFixture, provider_capabilities: providerCapabilities }),
  );

  render(<App csrfToken="csrf-example" fetchImpl={withAdminSession(fetchImpl)} />);
  await screen.findByRole("heading", { name: "Platform Integrations" });
  fireEvent.click(await screen.findByRole("button", { name: "Connect Rime" }));
  await screen.findByLabelText("API key");
  fireEvent.change(screen.getByLabelText("API key"), { target: { value: "synthetic-rime" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(await screen.findByRole("alert", { name: "Notification" })).toHaveTextContent(
    "Credentials could not be saved",
  );
  expect(screen.getByRole("dialog", { name: "Rime" })).toBeVisible();
  expect(screen.getByLabelText("API key")).toBeEnabled();
});

test("keeps Save usable when a platform credential cannot be tested", async () => {
  window.history.replaceState({}, "", "/platform/services/ai");
  let saved = false;
  const fetchImpl = vi.fn(
    async (_url: RequestInfo | URL, options?: RequestInit) => {
      if (String(_url).endsWith("/credentials/test")) {
        return response(
          { error: { code: "credential_validation_unsupported" } },
          501,
        );
      }
      if (options?.method === "POST") {
        saved = true;
        return response({ credential: { id: "rime-id" } }, 201);
      }
      return response({
        tenant: null,
        model_catalog: modelCatalogFixture, provider_capabilities: providerCapabilities,
        bindings: saved ? [binding("rime")] : [],
      });
    },
  );

  render(<App csrfToken="csrf-example" fetchImpl={withAdminSession(fetchImpl)} />);
  await screen.findByRole("heading", { name: "Platform Integrations" });
  fireEvent.click(await screen.findByRole("button", { name: "Connect Rime" }));
  await screen.findByLabelText("API key");
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-rime" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Test credentials" }));

  await waitFor(() => expect(screen.getByRole("button", { name: "Test credentials" })).toHaveAttribute("aria-disabled", "true"));
  expect(screen.getByRole("button", { name: "Save" })).toBeEnabled();

  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/api/platform/credentials",
    expect.objectContaining({
      method: "POST",
      body: JSON.stringify({
        provider: "rime",
        name: "rime",
        values: { api_key: "synthetic-rime" },
      }),
    }),
  );
});

test("directory outage is retryable and an expired session never looks like empty setup", async () => {
  window.history.replaceState({}, "", "/platform/services/ai");
  const expired = vi.fn();
  const fetchImpl = vi
    .fn()
    .mockImplementationOnce(() => response({}, 503))
    .mockImplementationOnce(() => response({}, 401));
  render(
    <App
      csrfToken="csrf-example"
      fetchImpl={withAdminSession(fetchImpl)}
      onSessionExpired={expired}
    />,
  );
  expect(
    await screen.findByText("Connection status unavailable"),
  ).toBeVisible();
  fireEvent.click(await screen.findByRole("button", { name: "Retry connections" }));
  await waitFor(() => expect(expired).toHaveBeenCalledTimes(1));
  expect(
    screen.queryByRole("button", { name: "Connect a service" }),
  ).not.toBeInTheDocument();
});
