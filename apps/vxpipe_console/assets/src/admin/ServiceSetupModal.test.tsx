import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { ServiceSetupModal } from "./ServiceSetupModal";

afterEach(cleanup);

test.each([
  {kind: "platform"} as const,
  {kind: "tenant", tenantKey: "demo", tenantName: "Demo"} as const,
])("Cartesia saves a private key for the selected scope: %j", (scope) => {
  const submit = vi.fn();
  render(<ServiceSetupModal state={{provider: "cartesia", status: "idle"}} scope={scope} onClose={vi.fn()} onSelect={vi.fn()} onSubmit={submit} onTest={vi.fn()} />);
  expect(screen.getByRole("dialog", {name: "Connect Cartesia"})).toBeVisible();
  expect(screen.getByText("Text-to-speech")).toBeVisible();
  expect(screen.getByText("Speech-to-text")).toBeVisible();
  expect(screen.getByLabelText("API key")).toHaveAttribute("type", "password");
  expect(screen.getByRole("button", {name: "Test credentials"})).toBeDisabled();
  fireEvent.change(screen.getByLabelText("API key"), {target: {value: "synthetic-cartesia"}});
  fireEvent.click(screen.getByRole("button", {name: "Save"}));
  expect(submit).toHaveBeenCalledWith({provider: "cartesia", values: {apiKey: "synthetic-cartesia"}});
});

test.each([
  {kind: "platform"} as const,
  {kind: "tenant", tenantKey: "demo", tenantName: "Demo"} as const,
])("ElevenLabs saves its single private key for the selected scope: %j", (scope) => {
  const submit = vi.fn();
  render(<ServiceSetupModal state={{provider: "elevenlabs", status: "idle"}} scope={scope} onClose={vi.fn()} onSelect={vi.fn()} onSubmit={submit} onTest={vi.fn()} />);
  expect(screen.getByRole("dialog", {name: "Connect ElevenLabs"})).toBeVisible();
  expect(screen.getByText("Text-to-speech")).toBeVisible();
  expect(screen.queryByText("Speech-to-text")).not.toBeInTheDocument();
  expect(screen.queryByText("Speech-to-speech")).not.toBeInTheDocument();
  expect(screen.getByLabelText("API key")).toHaveAttribute("type", "password");
  expect(screen.getByRole("button", {name: "Test credentials"})).toBeDisabled();
  fireEvent.change(screen.getByLabelText("API key"), {target: {value: "synthetic-elevenlabs"}});
  fireEvent.click(screen.getByRole("button", {name: "Save"}));
  expect(submit).toHaveBeenCalledWith({provider: "elevenlabs", values: {apiKey: "synthetic-elevenlabs"}});
});

test("credential dialog keeps only its edit actions", () => {
  render(
    <ServiceSetupModal
      state={{ provider: "deepgram", status: "idle" }}
      connections={[{ provider: "deepgram", status: "connected", source: "platform" }]}
      scope={{ kind: "platform" }}
      onClose={vi.fn()}
      onSelect={vi.fn()}
      onSubmit={vi.fn()}
      onTest={vi.fn(async () => ({ status: "valid" as const }))}
    />,
  );

  const actions = within(screen.getByRole("group", { name: "Credential actions" }));
  for (const name of ["Cancel", "Test credentials", "Save"]) {
    expect(actions.getByRole("button", { name })).toBeVisible();
  }
  expect(screen.queryByRole("button", { name: /Remove/ })).not.toBeInTheDocument();
});

test.each([
  { saved: false, publicKey: false, overriding: false },
  { saved: true, publicKey: false, overriding: false },
  { saved: true, publicKey: true, overriding: false },
  { saved: true, publicKey: true, overriding: true },
])("masks only saved fields when editing: %j", ({ saved, publicKey, overriding }) => {
  render(
    <ServiceSetupModal
      state={{ provider: "telnyx", status: "idle", overriding }}
      connections={
        saved
          ? [{
              provider: "telnyx",
              status: "connected",
              source: overriding ? "platform" : "tenant",
              telephonyPublicKeyConfigured: publicKey,
            }]
          : []
      }
      scope={{ kind: "tenant", tenantKey: "demo", tenantName: "Demo" }}
      publicOrigin="http://localhost:4000"
      onClose={vi.fn()}
      onSelect={vi.fn()}
      onSubmit={vi.fn()}
    />,
  );
  const apiInput = screen.getByLabelText("API key") as HTMLInputElement;
  const publicInput = screen.getByLabelText("Public key") as HTMLInputElement;
  expect(apiInput.placeholder).toBe(saved && !overriding ? "••••••••" : "");
  expect(publicInput.placeholder).toBe(
    saved && publicKey && !overriding ? "••••••••" : "",
  );
  expect(apiInput).toHaveValue("");
  expect(publicInput).toHaveValue("");
});
