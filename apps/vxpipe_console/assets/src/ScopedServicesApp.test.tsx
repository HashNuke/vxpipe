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
const providerCapabilities = {
  deepgram: ["credential", "stt", "tts"],
  google: ["credential"],
  rime: ["credential"],
  telnyx: ["credential", "telephony"],
  twilio: ["credential", "telephony"],
  zenmux: ["credential"],
};

test("platform displays existing Telnyx and Deepgram once without writing credentials", async () => {
  window.history.replaceState({}, "", "/admin/platform/services");
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, options?: RequestInit) => {
    if (options?.method && options.method !== "GET") throw new Error("unexpected credential write");
    return response({
          tenant: null,
          bindings: [
            { ...binding("telnyx"), platform_available: false },
            { ...binding("deepgram"), platform_available: false },
          ],
          provider_capabilities: providerCapabilities,
        });
  });

  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  expect(await screen.findByRole("article", { name: "Telnyx" })).toBeVisible();
  expect(screen.getAllByRole("article", { name: "Telnyx" })).toHaveLength(1);
  expect(screen.getAllByRole("article", { name: "Deepgram" })).toHaveLength(1);
  expect(screen.getAllByRole("button", { name: "Connect a service" })).toHaveLength(1);
  expect(screen.queryByRole("heading", { name: "AI providers" })).not.toBeInTheDocument();
  expect(screen.queryByRole("heading", { name: "Telephony" })).not.toBeInTheDocument();
  expect(fetchImpl.mock.calls.every(([, options]) => !options?.method || options.method === "GET")).toBe(true);
});

test("Setup picker offers installed services with only working capability badges", async () => {
  window.history.replaceState({}, "", "/admin/platform/services");
  const fetchImpl = vi.fn(async () => response({
    tenant: null,
    bindings: [],
    provider_capabilities: providerCapabilities,
  }));
  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  await screen.findByRole("heading", { name: "Platform services" });

  fireEvent.click(screen.getAllByRole("button", { name: "Connect a service" })[0]);
  const picker = screen.getByRole("combobox", { name: "Service" });
  expect(picker).toHaveTextContent("Zenmux");
  expect(picker).not.toHaveTextContent("Google Vertex AI");
  fireEvent.change(picker, { target: { value: "google" } });
  const dialog = screen.getByRole("dialog", { name: "Connect Google AI Studio" });
  expect(dialog).toHaveTextContent("LLM");
  expect(dialog).not.toHaveTextContent("Speech-to-text");
  expect(dialog).not.toHaveTextContent("Text-to-speech");
  expect(dialog).not.toHaveTextContent("Speech-to-speech");

  fireEvent.change(picker, { target: { value: "rime" } });
  expect(screen.getByRole("dialog", { name: "Connect Rime" })).not.toHaveTextContent("Credentials only");
  expect(screen.getByRole("dialog", { name: "Connect Rime" })).not.toHaveTextContent("Text-to-speech");
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
  fireEvent.click(screen.getByRole("button", { name: "Connect a service" }));
  expect(screen.getByRole("combobox", { name: "Service" })).toHaveTextContent("Twilio");
  expect(screen.getByRole("combobox", { name: "Service" })).toHaveTextContent("Rime");
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
          provider_capabilities: providerCapabilities,
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
  fireEvent.click(screen.getByRole("button", { name: "Connect a service" }));
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
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(screen.getByRole("status", { name: "Notification" })).toHaveTextContent("Service saved.");
  expect(screen.getByRole("status", { name: "Notification" })).toHaveClass("fixed");
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

test("platform services test and save separately, then edit the exact persisted binding", async () => {
  window.history.replaceState({}, "", "/admin/platform/services");
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
      return new Response(JSON.stringify({ tenant: null, bindings, provider_capabilities: providerCapabilities }));
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
  fireEvent.click(screen.getByRole("button", { name: "Test credentials" }));
  expect(await screen.findByText("Credentials tested successfully.")).toBeVisible();
  expect(screen.getByRole("dialog")).toBeVisible();
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/platform/credentials/test",
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
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
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
  expect(screen.queryByRole("button", { name: "Remove credentials" })).not.toBeInTheDocument();
  fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
  const card = screen.getByRole("article", { name: "Deepgram" });
  fireEvent.click(within(card).getByRole("button", { name: "More actions for Deepgram" }));
  fireEvent.click(screen.getByRole("button", { name: "Remove credentials" }));
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

test("failed card removal keeps the credentials visible and reports the error", async () => {
  window.history.replaceState({}, "", "/admin/platform/services");
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, options?: RequestInit) =>
    options?.method === "DELETE"
      ? response({ error: { code: "in_use" } }, 409)
      : response({
          tenant: null,
          bindings: [binding("deepgram")],
          provider_capabilities: providerCapabilities,
        }),
  );

  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  const card = await screen.findByRole("article", { name: "Deepgram" });
  fireEvent.click(within(card).getByRole("button", { name: "More actions for Deepgram" }));
  fireEvent.click(screen.getByRole("button", { name: "Remove credentials" }));

  expect(await screen.findByRole("alert", { name: "Notification" })).toHaveTextContent(
    /credential is used by a telephony service/,
  );
  expect(screen.getByRole("article", { name: "Deepgram" })).toBeVisible();
});

test("platform save failure appears in a page notification while the form stays open", async () => {
  window.history.replaceState({}, "", "/admin/platform/services");
  const fetchImpl = vi.fn(async (_url: RequestInfo | URL, options?: RequestInit) =>
    options?.method === "POST"
      ? response({ error: { code: "unavailable" } }, 503)
      : response({ tenant: null, bindings: [], provider_capabilities: providerCapabilities }),
  );

  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  await screen.findByRole("heading", { name: "Platform services" });
  fireEvent.click(screen.getByRole("button", { name: "Connect a service" }));
  fireEvent.change(screen.getByLabelText("Service"), { target: { value: "rime" } });
  fireEvent.change(screen.getByLabelText("API key"), { target: { value: "synthetic-rime" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));

  expect(await screen.findByRole("alert", { name: "Notification" })).toHaveTextContent(
    "Credentials could not be saved",
  );
  expect(screen.getByRole("dialog", { name: "Connect Rime" })).toBeVisible();
  expect(screen.getByLabelText("API key")).toBeEnabled();
});

test("keeps Save usable when a platform credential cannot be tested", async () => {
  window.history.replaceState({}, "", "/admin/platform/services");
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
        provider_capabilities: providerCapabilities,
        bindings: saved ? [binding("rime")] : [],
      });
    },
  );

  render(<App csrfToken="csrf-example" fetchImpl={fetchImpl} />);
  await screen.findByRole("heading", { name: "Platform services" });
  fireEvent.click(
    screen.getAllByRole("button", { name: "Connect a service" })[0],
  );
  fireEvent.change(screen.getByLabelText("Service"), {
    target: { value: "rime" },
  });
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "synthetic-rime" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Test credentials" }));

  expect(
    await screen.findByText(
      "Credential testing is not available for this service. You can still save it.",
    ),
  ).toBeVisible();
  expect(screen.getByRole("button", { name: "Save" })).toBeEnabled();

  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  await waitFor(() =>
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(),
  );
  expect(fetchImpl).toHaveBeenCalledWith(
    "/admin/api/platform/credentials",
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
  expect(
    await screen.findByRole("heading", { name: "Platform services unavailable" }),
  ).toBeVisible();
  expect(
    screen.getByText("Platform services could not be loaded. Try again."),
  ).toBeVisible();
  fireEvent.click(await screen.findByRole("button", { name: "Retry services" }));
  await waitFor(() => expect(expired).toHaveBeenCalledTimes(1));
  expect(
    screen.queryByRole("button", { name: "Connect a service" }),
  ).not.toBeInTheDocument();
});
