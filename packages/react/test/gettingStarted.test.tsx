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
  expect(screen.getByText("Service credentials")).toBeVisible();
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
  fireEvent.click(screen.getByRole("button", { name: "Choose services" }));
  fireEvent.change(screen.getByLabelText("STT API key"), {
    target: { value: "sample" },
  });
  fireEvent.change(screen.getByLabelText("TTS API key"), {
    target: { value: "sample" },
  });
  fireEvent.change(screen.getByLabelText("LLM API key"), {
    target: { value: "sample" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Validate credentials" }));
  expect(screen.getByText("3 of 4 steps complete")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Load sample definitions" }));
  expect(screen.getByText("Setup complete")).toBeVisible();
  expect(
    screen.getByRole("button", { name: "Try voice conversation" }),
  ).toBeEnabled();
});

test("onboarding validates selected services before offering sample definitions", () => {
  render(<GettingStarted ready={false} onTry={() => {}} />);

  fireEvent.click(screen.getByRole("button", { name: "Rename tenant" }));
  fireEvent.change(screen.getByRole("textbox", { name: "Tenant name" }), {
    target: { value: "Acme voice lab" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Save tenant name" }));
  fireEvent.click(screen.getByRole("button", { name: "Choose services" }));
  fireEvent.click(screen.getByRole("checkbox", { name: "Telephony" }));

  fireEvent.change(screen.getByLabelText("STT API key"), {
    target: { value: "stt-sample" },
  });
  fireEvent.change(screen.getByLabelText("TTS API key"), {
    target: { value: "tts-sample" },
  });
  fireEvent.change(screen.getByLabelText("LLM API key"), {
    target: { value: "llm-sample" },
  });
  fireEvent.change(screen.getByLabelText("Telephony API key"), {
    target: { value: "telephony-sample" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Validate credentials" }));

  expect(screen.getByText(/All selected services validated/)).toBeVisible();
  expect(screen.getAllByText(/Last validated just now/)[0]).toBeVisible();
  expect(screen.getByRole("button", { name: "Load sample definitions" })).toBeEnabled();
});
