import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { App } from "./App";

const tenant = {
  key: "AAAAAAAAAAAAAAAA",
  name: "Demo",
  created_at: "2026-09-19T01:00:00Z",
};
const binding = (provider: string, status = "connected", name = provider) => ({
  provider,
  name,
  source: "platform",
  status,
  credential_id: `${provider}-id`,
  platform_available: true,
  saved_fields: [],
  last_validated_at: null,
});

const response = (body: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(body), { status }));

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/admin");
});

test("an unavailable optional service does not block sample readiness or progress", async () => {
  window.history.replaceState({}, "", "/admin/onboarding");
  const fetchImpl = vi.fn((url: RequestInfo | URL) =>
    url === "/admin/api/onboarding/demo-tenant"
      ? response({ tenant })
      : response({
          tenant,
          bindings: [
            binding("google"),
            binding("deepgram"),
            binding("telnyx", "unavailable"),
          ],
        }),
  );
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  expect(
    await screen.findByRole("button", { name: "Load sample call specs" }),
  ).toBeEnabled();
  expect(
    within(screen.getByRole("list", { name: "Setup progress" })).getByText(
      "Connected",
    ),
  ).toBeVisible();
});

test("retries a failed effective directory read without treating it as empty setup", async () => {
  window.history.replaceState({}, "", "/admin/onboarding");
  let available = false;
  const fetchImpl = vi.fn((url: RequestInfo | URL) => {
    if (url === "/admin/api/onboarding/demo-tenant")
      return response({ tenant });
    return available
      ? response({ tenant, bindings: [binding("google"), binding("deepgram")] })
      : response({}, 503);
  });
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  expect(await screen.findByRole("alert")).toBeVisible();
  expect(
    screen.queryByRole("button", { name: "Load sample call specs" }),
  ).not.toBeInTheDocument();
  available = true;
  fireEvent.click(screen.getByRole("button", { name: "Retry setup" }));
  expect(
    await screen.findByRole("button", { name: "Load sample call specs" }),
  ).toBeEnabled();
  expect(screen.queryByText("Inherited from platform")).not.toBeInTheDocument();
});

test("onboarding counts inherited services and opens the tenant service inventory", async () => {
  window.history.replaceState({}, "", "/admin/onboarding");
  const fetchImpl = vi.fn((url: RequestInfo | URL) => {
    if (url === "/admin/api/onboarding/demo-tenant")
      return response({ tenant });
    if (String(url).endsWith("/service-bindings"))
      return response({
        tenant,
        bindings: [binding("google"), binding("deepgram")],
      });
    if (String(url).endsWith("/services"))
      return response({
        tenant: { key: tenant.key, name: tenant.name },
        credentials: [],
        telephony_services: [],
        truncated: false,
      });
    return response({}, 404);
  });
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  expect(
    await screen.findByRole("button", { name: "Load sample call specs" }),
  ).toBeEnabled();
  expect(screen.queryByText("Inherited from platform")).not.toBeInTheDocument();
  expect(
    screen.queryByRole("heading", { name: "Google AI Studio" }),
  ).not.toBeInTheDocument();
  expect(
    screen.queryByRole("heading", { name: "Deepgram" }),
  ).not.toBeInTheDocument();
  expect(screen.getByText("No tenant credentials configured.")).toBeVisible();
  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Manage services" }));
  expect(await screen.findByText("No services yet")).toBeVisible();
  expect(window.location.pathname).toBe(
    "/admin/tenants/AAAAAAAAAAAAAAAA/services",
  );
});

test("unavailable and alternate named bindings cannot make onboarding samples ready", async () => {
  window.history.replaceState({}, "", "/admin/onboarding");
  const fetchImpl = vi.fn((url: RequestInfo | URL) =>
    url === "/admin/api/onboarding/demo-tenant"
      ? response({ tenant })
      : response({
          tenant,
          bindings: [
            binding("google"),
            binding("deepgram", "unavailable"),
            binding("deepgram", "connected", "another-speech"),
          ],
        }),
  );
  render(<App csrfToken="csrf" fetchImpl={fetchImpl} />);
  await screen.findByRole("button", { name: "Manage services" });
  expect(
    screen.queryByRole("button", { name: "Load sample call specs" }),
  ).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Manage services" })).toBeEnabled();
});
