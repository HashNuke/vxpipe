import { useState } from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { TextField } from "./FormControls";

afterEach(cleanup);
const pem = "-----BEGIN PRIVATE KEY-----\nsynthetic-key-data\n-----END PRIVATE KEY-----";
function KeyEntry() {
  const [value, setValue] = useState("");
  return <TextField label="Private key (PEM)" secret multiline value={value} onChange={event => setValue(event.target.value)} />;
}

test("multiline secrets require reveal to edit and preserve line breaks through hiding", () => {
  render(<KeyEntry />);
  expect(screen.getByLabelText("Private key (PEM)")).toHaveAttribute("readonly");
  fireEvent.click(screen.getByRole("button", { name: "Show private key (pem)" }));
  const input = screen.getByLabelText("Private key (PEM)");
  fireEvent.change(input, { target: { value: pem } });
  expect(input).toHaveValue(pem);
  fireEvent.click(screen.getByRole("button", { name: "Hide private key (pem)" }));
  expect(screen.getByLabelText("Private key (PEM)")).toHaveAttribute("readonly");
  expect(screen.getByLabelText("Private key (PEM)")).not.toHaveValue(pem);
  fireEvent.click(screen.getByRole("button", { name: "Show private key (pem)" }));
  expect(screen.getByLabelText("Private key (PEM)")).toHaveValue(pem);
});

test("revealing a multiline secret preserves field constraints", () => {
  render(<TextField label="Private key" secret multiline value={pem} disabled required maxLength={16384} />);
  fireEvent.click(screen.getByRole("button", { name: "Show private key" }));
  const input = screen.getByLabelText("Private key");
  expect(input).toBeDisabled();
  expect(input).toBeRequired();
  expect(input).toHaveAttribute("maxlength", "16384");
});
