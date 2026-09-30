import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { ServiceCredentialForm } from "./ServiceCredentialForm";

afterEach(cleanup);

test("credential setup offers the installed provider catalog", () => {
  render(<ServiceCredentialForm onCancel={vi.fn()} onSubmit={vi.fn()} status="idle" />);
  const provider = screen.getByLabelText("Provider");
  expect(provider).toHaveTextContent("Rime");
  expect(provider).toHaveTextContent("Zenmux");
  expect(provider).toHaveTextContent("OpenAI");
  expect(provider).toHaveTextContent("Twilio");
  expect(provider).not.toHaveTextContent("Google Vertex AI");
});

test("OpenAI setup submits only one API key", () => {
  const submit = vi.fn();
  render(
    <ServiceCredentialForm
      initialProvider="openai"
      onCancel={vi.fn()}
      onSubmit={submit}
      status="idle"
    />,
  );

  expect(screen.getByLabelText("API key")).toHaveAttribute("type", "password");
  expect(screen.queryByLabelText("Account SID")).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("API key"), { target: { value: "synthetic-openai-key" } });
  fireEvent.submit(screen.getByRole("form", { name: "Credential setup" }));
  expect(submit).toHaveBeenCalledWith({
    provider: "openai",
    values: { apiKey: "synthetic-openai-key" },
  });
});

test("an unsupported stored provider does not get a generic credential form", () => {
  render(
    <ServiceCredentialForm
      initialProvider="vertex_ai"
      onCancel={vi.fn()}
      onSubmit={vi.fn()}
      status="idle"
    />,
  );

  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  expect(screen.getByRole("alert")).toHaveTextContent(
    "Credential setup is unavailable for this provider",
  );
  expect(screen.getByRole("button", { name: "Save" })).toBeDisabled();
});

test("shows only the credential fields owned by the selected provider", () => {
  render(
    <ServiceCredentialForm
      onCancel={vi.fn()}
      onSubmit={vi.fn()}
      status="idle"
    />,
  );

  expect(screen.getByLabelText("API key")).toHaveAttribute("type", "password");
  fireEvent.change(screen.getByLabelText("Provider"), {
    target: { value: "twilio" },
  });

  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  expect(screen.getByLabelText("Account SID")).toHaveAttribute(
    "type",
    "password",
  );
  expect(screen.getByLabelText("Auth token")).toHaveAttribute(
    "type",
    "password",
  );
});

test("submits provider credentials without rendering them as stored metadata", () => {
  const submit = vi.fn();
  render(
    <ServiceCredentialForm
      onCancel={vi.fn()}
      onSubmit={submit}
      status="idle"
    />,
  );

  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "secret-value" },
  });
  fireEvent.submit(screen.getByRole("form", { name: "Credential setup" }));

  expect(submit).toHaveBeenCalledWith({
    provider: "google",
    values: { apiKey: "secret-value" },
  });
  expect(screen.queryByText("secret-value")).not.toBeInTheDocument();
});

test("tests credentials without saving, then saves with a separate action", async () => {
  const testCredentials = vi.fn(async () => ({ status: "valid" as const }));
  const submit = vi.fn();
  render(
    <ServiceCredentialForm
      onCancel={vi.fn()}
      onSubmit={submit}
      onTest={testCredentials}
      status="idle"
    />,
  );

  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "secret-value" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Test credentials" }));

  await waitFor(() => expect(testCredentials).toHaveBeenCalledOnce());
  expect(submit).not.toHaveBeenCalled();
  expect(screen.getByRole("status")).toHaveTextContent(
    "Credentials tested successfully",
  );
  expect(screen.getByLabelText("API key")).toHaveValue("secret-value");

  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(submit).toHaveBeenCalledWith({
    provider: "google",
    values: { apiKey: "secret-value" },
  });
});

test("keeps Save available when credential testing is unsupported", async () => {
  const submit = vi.fn();
  render(
    <ServiceCredentialForm
      onCancel={vi.fn()}
      onSubmit={submit}
      onTest={async () => ({
        status: "unsupported",
        message: "Credential testing is not available for this service.",
      })}
      status="idle"
    />,
  );

  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "secret-value" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Test credentials" }));

  expect(await screen.findByRole("status")).toHaveTextContent(
    "Credential testing is not available",
  );
  expect(screen.getByRole("button", { name: "Save" })).toBeEnabled();
});

test("does not submit incomplete credentials", () => {
  const submit = vi.fn();
  render(
    <ServiceCredentialForm
      onCancel={vi.fn()}
      onSubmit={submit}
      status="idle"
    />,
  );

  fireEvent.submit(screen.getByRole("form", { name: "Credential setup" }));

  expect(submit).not.toHaveBeenCalled();
  expect(screen.getByRole("alert")).toHaveTextContent(
    "Enter a valid API key without spaces or line breaks",
  );
});

test("rejects malformed provider values before submission", () => {
  const submit = vi.fn();
  render(
    <ServiceCredentialForm
      onCancel={vi.fn()}
      onSubmit={submit}
      status="idle"
    />,
  );
  fireEvent.change(screen.getByLabelText("Provider"), {
    target: { value: "twilio" },
  });
  fireEvent.change(screen.getByLabelText("Account SID"), {
    target: { value: "not-a-sid" },
  });
  fireEvent.change(screen.getByLabelText("Auth token"), {
    target: { value: "token" },
  });
  fireEvent.submit(screen.getByRole("form", { name: "Credential setup" }));

  expect(submit).not.toHaveBeenCalled();
  expect(screen.getByRole("alert")).toHaveTextContent(
    "valid Twilio Account SID",
  );
});

test("clears secret fields after success and cancel", () => {
  const cancel = vi.fn();
  const view = render(
    <ServiceCredentialForm
      onCancel={cancel}
      onSubmit={vi.fn()}
      status="idle"
    />,
  );
  const apiKey = screen.getByLabelText("API key");
  fireEvent.change(apiKey, { target: { value: "first-secret" } });

  view.rerender(
    <ServiceCredentialForm
      onCancel={cancel}
      onSubmit={vi.fn()}
      status="success"
    />,
  );
  expect(screen.getByLabelText("API key")).toHaveValue("");

  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "second-secret" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(cancel).toHaveBeenCalledOnce();
  expect(screen.getByLabelText("API key")).toHaveValue("");
});

test("clears secret fields after the backend rejects a credential", () => {
  const view = render(
    <ServiceCredentialForm
      onCancel={vi.fn()}
      onSubmit={vi.fn()}
      status="submitting"
    />,
  );
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "rejected-secret" },
  });

  view.rerender(
    <ServiceCredentialForm
      message="A credential with this provider and name already exists."
      onCancel={vi.fn()}
      onSubmit={vi.fn()}
      status="conflict"
    />,
  );

  expect(screen.getByLabelText("API key")).toHaveValue("");
});

test("Telnyx accepts an API key alone or both keys, rejects malformed public keys, and clears drafts", () => {
  const submit = vi.fn();
  const view = render(
    <ServiceCredentialForm
      initialProvider="telnyx"
      showTelnyxPublicKey
      onCancel={vi.fn()}
      onSubmit={submit}
      status="idle"
    />,
  );
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "storybook-telnyx-key" },
  });
  fireEvent.submit(screen.getByRole("form", { name: "Credential setup" }));
  expect(submit).toHaveBeenCalledWith({
    provider: "telnyx",
    values: { apiKey: "storybook-telnyx-key" },
  });
  submit.mockClear();
  for (const value of ["not-base64", btoa("short")]) {
    fireEvent.change(screen.getByLabelText("Public key"), {
      target: { value },
    });
    fireEvent.submit(screen.getByRole("form", { name: "Credential setup" }));
    expect(submit).not.toHaveBeenCalled();
    expect(screen.getByRole("alert")).toHaveTextContent("public key");
  }
  const publicKey = btoa("p".repeat(32));
  fireEvent.change(screen.getByLabelText("Public key"), {
    target: { value: publicKey },
  });
  fireEvent.submit(screen.getByRole("form", { name: "Credential setup" }));
  expect(submit).toHaveBeenCalledWith({
    provider: "telnyx",
    values: { apiKey: "storybook-telnyx-key", publicKey },
  });
  view.rerender(
    <ServiceCredentialForm
      initialProvider="telnyx"
      showTelnyxPublicKey
      onCancel={vi.fn()}
      onSubmit={submit}
      status="success"
    />,
  );
  expect(screen.getByLabelText("API key")).toHaveValue("");
  expect(screen.getByLabelText("Public key")).toHaveValue("");
});

for (const provider of ["deepseek", "openrouter", "fireworks", "cartesia"] as const) {
  test(`${provider} setup submits its single private key`, () => {
    const submit = vi.fn();
    render(<ServiceCredentialForm initialProvider={provider} onCancel={vi.fn()} onSubmit={submit} status="idle" />);
    fireEvent.change(screen.getByLabelText("API key"), { target: { value: "synthetic-key" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(submit).toHaveBeenCalledWith({ provider, values: { apiKey: "synthetic-key" } });
  });
}

for (const provider of ["fireworks", "cartesia"] as const) {
test(`${provider} saves independently and does not offer an unsupported credential probe`, () => {
  const probe = vi.fn();
  const submit = vi.fn();
  render(<ServiceCredentialForm initialProvider={provider} onCancel={vi.fn()} onSubmit={submit} onTest={probe} status="idle" />);
  fireEvent.change(screen.getByLabelText("API key"), { target: { value: "synthetic-key" } });
  const testButton = screen.getByRole("button", { name: "Test credentials" });
  expect(testButton).toBeDisabled();
  expect(screen.getByText("Credential testing is unavailable for this provider. You can save its API key and verify it with a call.")).toBeInTheDocument();
  fireEvent.click(testButton);
  expect(probe).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole("button", { name: "Save" }));
  expect(submit).toHaveBeenCalledWith({ provider, values: { apiKey: "synthetic-key" } });
});
}
