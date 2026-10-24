import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { AuthPage } from "./AuthPage";

afterEach(cleanup);

test("setup starts with the current origin, then saves the chosen URL with the superadmin", async () => {
  const submit = vi.fn().mockResolvedValue({});
  render(<AuthPage mode="setup" configureUrl onSubmit={submit} />);
  expect(screen.getByLabelText("Installation URL")).toHaveValue(window.location.origin);
  expect(screen.queryByLabelText("Email")).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("Installation URL"), { target: { value: "https://calls.example.test:8443/admin/setup?tab=url#address" } });
  fireEvent.click(screen.getByRole("button", { name: /Continue/ }));
  expect(submit).not.toHaveBeenCalled();
  fireEvent.change(screen.getByLabelText("Email"), { target: { value: "owner@example.test" } });
  fireEvent.change(screen.getByLabelText("Password"), { target: { value: "an example passphrase" } });
  fireEvent.change(screen.getByLabelText("Confirm password"), { target: { value: "an example passphrase" } });
  fireEvent.click(screen.getByRole("button", { name: /Back/ }));
  expect(screen.getByLabelText("Installation URL")).toHaveValue("https://calls.example.test:8443");
  fireEvent.click(screen.getByRole("button", { name: /Continue/ }));
  expect(screen.getByLabelText("Email")).toHaveValue("owner@example.test");
  fireEvent.click(screen.getByRole("button", { name: /Create Superadmin/ }));
  await waitFor(() => expect(submit).toHaveBeenCalledWith("owner@example.test", "an example passphrase", undefined, "https://calls.example.test:8443"));
});

test("an invalid URL cannot advance to account creation", () => {
  render(<AuthPage mode="setup" configureUrl onSubmit={vi.fn()} />);
  fireEvent.change(screen.getByLabelText("Installation URL"), { target: { value: "http://calls.example.test/admin" } });
  fireEvent.click(screen.getByRole("button", { name: /Continue/ }));
  expect(screen.getByRole("alert")).toHaveTextContent(/HTTPS/);
  expect(screen.queryByLabelText("Email")).not.toBeInTheDocument();
});
