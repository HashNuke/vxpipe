import { fireEvent, render, screen } from "@testing-library/react";
import { expect, test, vi } from "vitest";
import { GettingStarted } from "../stories/GettingStarted.js";
import { Workbench } from "../stories/Workbench.js";
import { waitFor } from "@testing-library/react";

test.each([
  ["agent handoff", "Delivery specialist"],
  ["human handoff", "Support teammate"],
])(
  "starting the %s example loads its own participants",
  async (example, participant) => {
    render(<Workbench page="setup" ready />);
    fireEvent.click(screen.getByRole("button", { name: `Try ${example}` }));
    fireEvent.click(screen.getByRole("button", { name: "Start call" }));
    await waitFor(() =>
      expect(screen.getAllByText(participant)[0]).toBeVisible(),
    );
  },
);

test("incomplete setup explains the missing dependency and blocks sample launch", () => {
  const onTry = vi.fn();
  render(<GettingStarted ready={false} onTry={onTry} />);
  expect(
    screen.getByRole("button", { name: "Try voice conversation" }),
  ).toBeDisabled();
  expect(screen.getByText("Speech + model services")).toBeVisible();
  expect(onTry).not.toHaveBeenCalled();
});

test("ready examples open the same console without automatically starting a call", () => {
  const onTry = vi.fn();
  render(<GettingStarted ready onTry={onTry} />);
  fireEvent.click(
    screen.getByRole("button", { name: "Try voice conversation" }),
  );
  expect(onTry).toHaveBeenCalledWith("voice");
  expect(screen.getByText("Setup complete")).toBeVisible();
});

test("setup progress follows service configuration and example installation", () => {
  render(<GettingStarted ready={false} onTry={() => {}} />);
  fireEvent.click(screen.getByRole("button", { name: "Configure services" }));
  fireEvent.change(screen.getByLabelText(/Deepgram API key/), {
    target: { value: "sample" },
  });
  fireEvent.change(screen.getByLabelText(/Google API key/), {
    target: { value: "sample" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save credentials" }));
  expect(screen.getByText("3 of 4 steps complete")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Install examples" }));
  expect(screen.getByText("Setup complete")).toBeVisible();
  expect(
    screen.getByRole("button", { name: "Try voice conversation" }),
  ).toBeEnabled();
});
