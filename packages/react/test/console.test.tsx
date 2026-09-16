import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { expect, test } from "vitest";
import { CallConsole } from "../src/index.js";
import { createFixtureClient } from "../stories/fixtureClient.js";

test("a denied microphone still allows typed input in the same conversation", async () => {
  const client = createFixtureClient("microphone-denied");
  render(<CallConsole client={client} />);
  fireEvent.change(screen.getByRole("textbox", { name: "Message" }), {
    target: { value: "Can we continue by text?" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Send message" }));
  await waitFor(() =>
    expect(screen.getByText("Can we continue by text?")).toBeVisible(),
  );
  expect(
    screen.getByRole("button", { name: "Enable microphone" }),
  ).toBeDisabled();
  expect(client.getSnapshot().callId).toBe("demo-call-001");
});

test("leaving keeps the transcript visible and disables further sending", async () => {
  const client = createFixtureClient("conversation");
  render(<CallConsole client={client} />);
  fireEvent.click(screen.getByRole("button", { name: "Leave call" }));
  await waitFor(() => expect(screen.getByText("Call ended")).toBeVisible());
  expect(screen.getByText("I'd like to reschedule my delivery.")).toBeVisible();
  expect(screen.getByRole("button", { name: "Send message" })).toBeDisabled();
});

test("Conversation filters messages, events, tool calls and raw RTVI logs", () => {
  render(<CallConsole client={createFixtureClient("human-handoff")} />);

  expect(screen.getByText("Support joined")).toBeVisible();
  expect(screen.getByText("update_variables")).toBeVisible();
  expect(screen.queryByText("client-ready")).not.toBeInTheDocument();

  fireEvent.click(screen.getByRole("button", { name: "Show Logs" }));
  expect(screen.getByText("client-ready")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Hide Events" }));
  expect(screen.queryByText("Support joined")).not.toBeInTheDocument();

  fireEvent.click(screen.getByRole("button", { name: "Reset filters" }));
  expect(screen.getByText("Support joined")).toBeVisible();
  expect(screen.queryByText("client-ready")).not.toBeInTheDocument();
});

test("unsupported alignment shows a speaking state without word highlighting", () => {
  render(<CallConsole client={createFixtureClient("no-alignment")} />);
  expect(screen.getByText("Word timing unavailable")).toBeVisible();
  expect(document.querySelector("mark")).toBeNull();
});

test("device menus expose styled options and apply the selected device", async () => {
  const client = createFixtureClient("conversation");
  render(<CallConsole client={client} />);

  fireEvent.click(screen.getByRole("combobox", { name: "Input device" }));
  fireEvent.click(await screen.findByRole("option", { name: "USB headset" }));

  await waitFor(() =>
    expect(client.getSnapshot().inputDevice).toBe("USB headset"),
  );
  expect(
    screen.getByRole("combobox", { name: "Input device" }),
  ).toHaveTextContent("USB headset");
});

test("Variables displays the latest authorized snapshot by section", () => {
  render(
    <CallConsole
      client={createFixtureClient("conversation")}
      initialTab="variables"
    />,
  );

  expect(screen.getByRole("heading", { name: "intake" })).toBeVisible();
  expect(screen.getByText("requested_date")).toBeVisible();
  expect(screen.getByText("2026-09-18")).toBeVisible();
});

test("Metrics groups measurements by their authoritative scope", () => {
  render(
    <CallConsole
      client={createFixtureClient("conversation")}
      initialTab="metrics"
    />,
  );

  expect(screen.getByRole("heading", { name: "Room" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "Room capability" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "Participant" })).toBeVisible();
  expect(
    screen.getByRole("heading", { name: "Participant capability" }),
  ).toBeVisible();
});

test("a message time exposes its correlated turn metrics on focus", async () => {
  render(<CallConsole client={createFixtureClient("conversation")} />);

  fireEvent.focus(
    screen.getByRole("button", {
      name: "View metrics for Assistant at 00:10",
    }),
  );

  expect(await screen.findByRole("tooltip")).toHaveTextContent(
    "First model token312 ms",
  );
});
