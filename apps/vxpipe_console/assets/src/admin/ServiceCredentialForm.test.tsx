import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";

import { ServiceCredentialForm } from "./ServiceCredentialForm";

afterEach(cleanup);

test("shows only the credential fields owned by the selected provider", () => {
  render(<ServiceCredentialForm onCancel={vi.fn()} onSubmit={vi.fn()} status="idle" />);

  expect(screen.getByLabelText("API key")).toHaveAttribute("type", "password");
  fireEvent.change(screen.getByLabelText("Provider"), {
    target: { value: "twilio" },
  });

  expect(screen.queryByLabelText("API key")).not.toBeInTheDocument();
  expect(screen.getByLabelText("Account SID")).toHaveAttribute("type", "password");
  expect(screen.getByLabelText("Auth token")).toHaveAttribute("type", "password");
});

test("submits provider credentials without rendering them as stored metadata", () => {
  const submit = vi.fn();
  render(<ServiceCredentialForm onCancel={vi.fn()} onSubmit={submit} status="idle" />);

  fireEvent.change(screen.getByLabelText("Credential name"), {
    target: { value: "primary" },
  });
  fireEvent.change(screen.getByLabelText("API key"), {
    target: { value: "secret-value" },
  });
  fireEvent.submit(screen.getByRole("form", { name: "Credential setup" }));

  expect(submit).toHaveBeenCalledWith({
    provider: "google",
    name: "primary",
    values: { apiKey: "secret-value" },
  });
  expect(screen.queryByText("secret-value")).not.toBeInTheDocument();
});

test("does not submit incomplete credentials", () => {
  const submit = vi.fn();
  render(<ServiceCredentialForm onCancel={vi.fn()} onSubmit={submit} status="idle" />);

  fireEvent.submit(screen.getByRole("form", { name: "Credential setup" }));

  expect(submit).not.toHaveBeenCalled();
  expect(screen.getByRole("alert")).toHaveTextContent(
    "Use letters, numbers, underscores or hyphens",
  );
});

test("rejects malformed provider values before submission", () => {
  const submit = vi.fn();
  render(<ServiceCredentialForm onCancel={vi.fn()} onSubmit={submit} status="idle" />);
  fireEvent.change(screen.getByLabelText("Provider"), { target: { value: "twilio" } });
  fireEvent.change(screen.getByLabelText("Credential name"), { target: { value: "phone" } });
  fireEvent.change(screen.getByLabelText("Account SID"), { target: { value: "not-a-sid" } });
  fireEvent.change(screen.getByLabelText("Auth token"), { target: { value: "token" } });
  fireEvent.submit(screen.getByRole("form", { name: "Credential setup" }));

  expect(submit).not.toHaveBeenCalled();
  expect(screen.getByRole("alert")).toHaveTextContent("valid Twilio Account SID");
});

test("clears secret fields after success and cancel", () => {
  const cancel = vi.fn();
  const view = render(
    <ServiceCredentialForm onCancel={cancel} onSubmit={vi.fn()} status="idle" />,
  );
  const apiKey = screen.getByLabelText("API key");
  fireEvent.change(apiKey, { target: { value: "first-secret" } });

  view.rerender(
    <ServiceCredentialForm onCancel={cancel} onSubmit={vi.fn()} status="success" />,
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
    <ServiceCredentialForm onCancel={vi.fn()} onSubmit={vi.fn()} status="submitting" />,
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
