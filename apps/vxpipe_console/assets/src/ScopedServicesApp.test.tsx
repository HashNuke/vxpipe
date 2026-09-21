import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
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
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
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
