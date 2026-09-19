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
  credential_id: `${provider}-id`,
  tenant_credential_id: null,
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
  ).not.toBeInTheDocument();
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
