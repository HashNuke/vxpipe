import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { OAuthConsent, type Consent } from "./OAuthConsent";

afterEach(() => { cleanup(); vi.restoreAllMocks(); });
const consent: Consent = {
  client_id: "registered-client", client_name: "Real client", client_uri: "https://client.example/about",
  logo_uri: "https://client.example/logo.png", user_email: "member@real.test",
  resource: "https://vxpipe.example/mcp", redirect_uri: "http://127.0.0.1:1455/callback",
  grant_lifetime_seconds: 2592000,
  authority: { grants: ["calls.read", "call_specs.write"], all_tenant_actions: ["calls.read"], assigned_tenants: { "tenant-one": "read_write" } },
};

test("native submission stays in the same tab and suppresses duplicate decisions", () => {
  const open = vi.spyOn(window, "open").mockReturnValue({} as Window);
  render(<OAuthConsent consent={consent} requestId="request" csrfToken="csrf" />);
  const form = screen.getByRole("button", { name: "Allow connection" }).closest("form")!;
  expect(fireEvent.submit(form)).toBe(true);
  expect(fireEvent.submit(form)).toBe(false);
  expect(open).not.toHaveBeenCalled();
  expect(form.target).toBe("");
  expect(screen.getByRole("status")).toHaveTextContent("Saving your choice");
  expect(new FormData(form).has("presentation")).toBe(false);
});

test.each(["allowed", "denied"] as const)("%s confirmation waits for Back to my app with the exact callback", (step) => {
  const open = vi.spyOn(window, "open");
  const returnToApp = vi.fn();
  const callback = `http://127.0.0.1:1455/callback?${step === "allowed" ? "code=example-code" : "error=access_denied"}&state=example-state&iss=https%3A%2F%2Fvxpipe.example`;
  render(<OAuthConsent consent={consent} requestId="request" csrfToken="" step={step} callbackUrl={callback} onReturnToApp={returnToApp} />);
  const back = screen.getByRole("link", { name: "Back to my app" });
  expect(back).toHaveAttribute("href", callback);
  expect(back).not.toHaveAttribute("target");
  expect(back).toHaveAttribute("rel", "noreferrer");
  expect(screen.queryByRole("button", { name: "Back to Vxpipe" })).not.toBeInTheDocument();
  expect(screen.queryByRole("link", { name: "Back to Vxpipe" })).not.toBeInTheDocument();
  expect(returnToApp).not.toHaveBeenCalled();
  expect(open).not.toHaveBeenCalled();
  fireEvent.click(back);
  expect(returnToApp).toHaveBeenCalledTimes(1);
});

test("the approved receipt displays the recorded expiry", () => {
  render(<OAuthConsent consent={consent} requestId="request" csrfToken="" step="allowed" expiresAt="2026-12-11T12:34:56Z" />);
  expect(document.querySelector("time")).toHaveAttribute("datetime", "2026-12-11T12:34:56Z");
  expect(screen.getByText("Continue in Real client to finish connecting to Vxpipe.")).toBeInTheDocument();
});

test("reserved user permissions have readable labels while retaining their exact keys", () => {
  render(<OAuthConsent consent={{ ...consent, authority: { grants: ["users.members.write", "users.admins.write", "users.superadmins.write", "platform_api_keys.read"], all_tenant_actions: [], assigned_tenants: {} } }} requestId="id" csrfToken="csrf" />);
  expect(screen.getByRole("heading", { name: "Manage member accounts" })).toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Manage Admin accounts" })).toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Manage Superadmin accounts" })).toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Read platform API keys" })).toBeInTheDocument();
  expect(screen.getByText("users.admins.write", { selector: "code" })).toBeInTheDocument();
});

test("production consent submits the opaque request with CSRF and the selected decision", () => {
  render(<OAuthConsent consent={consent} requestId="opaque-request" csrfToken="csrf-value" />);
  expect(screen.getByText("member@real.test")).toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Connect Real client to Vxpipe?" })).toBeInTheDocument();
  const allow = screen.getByRole("button", { name: "Allow connection" });
  const form = allow.closest("form")!;
  expect(form).toHaveAttribute("action", "/oauth/authorize/opaque-request");
  expect(form).toHaveAttribute("method", "post");
  expect(new FormData(form).get("_csrf_token")).toBe("csrf-value");
  expect(allow).toHaveAttribute("name", "decision");
  expect(allow).toHaveAttribute("value", "approve");
  expect(screen.getByRole("button", { name: "Deny" })).toHaveAttribute("value", "deny");
});

test("consent keeps all-tenant actions distinct from assigned-tenant authority", () => {
  render(<OAuthConsent consent={consent} requestId="id" csrfToken="csrf" />);
  expect(screen.getByText("Read calls", { selector: "h3" })).toBeInTheDocument();
  expect(screen.getByText("Write call specs", { selector: "h3" })).toBeInTheDocument();
  expect(screen.getByText("All tenants, including future tenants")).toBeInTheDocument();
  expect(screen.getByText("Read calls", { selector: ".oauth-preview-scope strong" })).toBeInTheDocument();
  expect(screen.getByText("tenant-one")).toBeInTheDocument();
  expect(screen.getByText("Read and write")).toBeInTheDocument();
  expect(screen.queryByText("Demo")).not.toBeInTheDocument();
  fireEvent.click(screen.getByText("Connection details"));
  expect(screen.getByText("registered-client")).toBeInTheDocument();
  expect(screen.getByText("http://127.0.0.1:1455/callback")).toBeInTheDocument();
});

test("empty authority never invents actions and unsafe branding is omitted", () => {
  render(<OAuthConsent consent={{ ...consent, client_name: "<script>client</script>", client_uri: "javascript:alert(1)", logo_uri: "https://user:pass@client.example/logo", authority: { grants: [], all_tenant_actions: [], assigned_tenants: {} } }} requestId="id" csrfToken="csrf" />);
  expect(screen.getByText("No action permissions available")).toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "Connect <script>client</script> to Vxpipe?" })).toBeInTheDocument();
  expect(document.querySelector("script")).toBeNull();
  expect(screen.getByRole("img", { name: "Client icon" })).toBeInTheDocument();
  expect(screen.queryByRole("link", { name: /alert/ })).not.toBeInTheDocument();
});
