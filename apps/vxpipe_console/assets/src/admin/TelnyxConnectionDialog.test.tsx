import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { TelnyxConnectionDialog } from "./TelnyxConnectionDialog";

afterEach(cleanup);
const base = {
  state: { provider: "telnyx" as const, status: "idle" as const },
  scope: { kind: "tenant" as const, tenantKey: "Acme123456789012", tenantName: "Acme" },
  connections: [{ provider: "telnyx" as const, source: "platform" as const, status: "connected" as const, savedFields: ["apiKey" as const, "publicKey" as const] }],
  platformConnections: [{ provider: "telnyx" as const, source: "platform" as const, status: "connected" as const }],
  platformApplicationId: "shared-app",
  webhookUrls: { platform: "https://calls.test/platform", tenant: "https://calls.test/Acme123456789012" },
  onClose: vi.fn(), onSubmit: vi.fn(), onUsePlatform: vi.fn(),
};

test("credential override clears the application and requires both keys and an application in one save", () => {
  const onSave = vi.fn();
  render(<TelnyxConnectionDialog {...base} onSave={onSave} />);
  fireEvent.click(screen.getByRole("button", { name: "Override credentials" }));
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("");
  expect(screen.getByDisplayValue(base.webhookUrls.tenant)).toBeVisible();
  expect(screen.queryByRole("button", { name: "Use platform default for voice application" })).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(onSave).not.toHaveBeenCalled();
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "acme-app" } });
  fireEvent.change(screen.getByLabelText("API key"), { target: { value: "synthetic-key" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(onSave).not.toHaveBeenCalled();
  fireEvent.change(screen.getByLabelText("Public key"), { target: { value: "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(onSave).toHaveBeenCalledWith({ application_id: "acme-app", credentials: {
    api_key: "synthetic-key", public_key: "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=",
  } });
});

test("application-only override uses a tenant URL and leaves credentials untouched", () => {
  const onSave = vi.fn();
  render(<TelnyxConnectionDialog {...base} onSave={onSave} />);
  fireEvent.click(screen.getByRole("button", { name: "Override voice application" }));
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "acme-app" } });
  expect(screen.getByDisplayValue(base.webhookUrls.tenant)).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(onSave).toHaveBeenCalledWith({ application_id: "acme-app" });
});

test("editing saved tenant credentials clears the app and omits unchanged masked keys", () => {
  const onSave = vi.fn();
  render(<TelnyxConnectionDialog {...base} applicationId="acme-app"
    connections={[{ ...base.connections[0], source: "tenant" }]} onSave={onSave} />);
  fireEvent.click(screen.getByRole("button", { name: "Edit credentials" }));
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("");
  fireEvent.change(screen.getByLabelText("Voice API application ID"), { target: { value: "acme-new-app" } });
  fireEvent.change(screen.getByLabelText("Public key"), { target: { value: "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=" } });
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(onSave).toHaveBeenCalledWith({ application_id: "acme-new-app", credentials: {
    public_key: "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=",
  } });
});

test("reset credentials keeps the app; resetting both restores the platform URL", () => {
  const onSave = vi.fn();
  render(<TelnyxConnectionDialog {...base} applicationId="acme-app"
    connections={[{ ...base.connections[0], source: "tenant" }]} onSave={onSave} />);
  fireEvent.click(screen.getByRole("button", { name: "Use platform default for credentials" }));
  expect(screen.getByLabelText("Voice API application ID")).toHaveValue("acme-app");
  fireEvent.click(screen.getByRole("button", { name: "Use platform default for voice application" }));
  expect(screen.getByDisplayValue(base.webhookUrls.platform)).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(onSave).toHaveBeenCalledWith({ application_id: null, credentials: null });
});

test("Cancel discards the draft without invoking save", () => {
  const onSave = vi.fn();
  render(<TelnyxConnectionDialog {...base} onSave={onSave} />);
  fireEvent.click(screen.getByRole("button", { name: "Override credentials" }));
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(onSave).not.toHaveBeenCalled();
  expect(base.onClose).toHaveBeenCalled();
});


test("credential-only writers can reset credentials while the application stays read-only", () => {
  const onSave = vi.fn();
  render(<TelnyxConnectionDialog {...base} applicationId="acme-app"
    connections={[{ ...base.connections[0], source: "tenant" }]}
    canEditCredentials canEditApplication={false} onSave={onSave} />);
  expect(screen.getByLabelText("Voice API application ID")).toHaveAttribute("readonly");
  expect(screen.queryByRole("button", { name: "Edit credentials" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Use platform default for credentials" }));
  expect(screen.queryByRole("button", { name: "Use platform default for voice application" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(onSave).toHaveBeenCalledWith({ credentials: null });
});
