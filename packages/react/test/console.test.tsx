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

test("Logs displays only RTVI traffic and can filter and inspect an event", () => {
  const client = createFixtureClient("conversation");
  render(<CallConsole client={client} initialTab="logs" />);
  fireEvent.change(
    screen.getByRole("searchbox", { name: "Filter RTVI events" }),
    { target: { value: "server-message" } },
  );
  expect(
    screen.queryByRole("button", { name: /bot-ready/ }),
  ).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: /server-message/ }));
  expect(screen.getByText(/vxpipe.turn/)).toBeVisible();
  expect(screen.queryByText("transport.connected")).not.toBeInTheDocument();
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
