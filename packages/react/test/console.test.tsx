import {
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
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

test("tool calls disclose optional request and response details", () => {
  render(<CallConsole client={createFixtureClient("tool-states")} />);

  const disclosure = screen.getByRole("button", {
    name: "Show details for update_variables",
  });
  expect(screen.queryByText("Request")).not.toBeInTheDocument();
  expect(
    screen.queryByRole("button", {
      name: "Show details for lookup_delivery",
    }),
  ).not.toBeInTheDocument();

  fireEvent.click(disclosure);
  expect(screen.getByText("Request")).toBeVisible();
  expect(screen.getByText("Response")).toBeVisible();
  expect(
    screen.getByText(/"requested_date": "2026-09-18"/),
  ).toBeVisible();

  fireEvent.click(
    screen.getByRole("button", {
      name: "Hide details for update_variables",
    }),
  );
  expect(screen.queryByText("Request")).not.toBeInTheDocument();
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

test("configured participants remain in the sidebar before joining", () => {
  render(<CallConsole client={createFixtureClient("ready")} />);

  expect(
    screen.getByRole("button", {
      name: "View Delivery specialist details",
    }),
  ).toHaveClass("vx-participant-muted");
  expect(
    screen.getByRole("button", { name: "View Support teammate details" }),
  ).toHaveClass("vx-participant-muted");
  expect(screen.queryByText("waiting", { exact: false })).not.toBeInTheDocument();
});

test("a sidebar participant opens their authorized configuration", () => {
  render(<CallConsole client={createFixtureClient("conversation")} />);

  const tabs = within(screen.getByRole("navigation", { name: "Call views" }))
    .getAllByRole("button")
    .map((button) => button.textContent);
  expect(tabs).toEqual([
    "Conversation",
    "Variables",
    "Metrics",
    "Participants",
  ]);

  fireEvent.click(
    screen.getByRole("button", { name: "View Assistant details" }),
  );

  expect(
    screen.getByRole("button", { name: "Participants" }),
  ).toHaveAttribute("aria-current", "page");
  expect(screen.getByRole("heading", { name: "Assistant" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "Capabilities" })).toBeVisible();
  expect(screen.getByText("gemini-2.5-flash")).toBeVisible();
  expect(screen.getByRole("heading", { name: "System prompt" })).toBeVisible();
  expect(screen.getByText(/delivery concierge for Acme/)).toBeVisible();
  expect(
    screen.getByRole("heading", { name: "Transfer policies" }),
  ).toBeVisible();
  expect(screen.getByText("Escalate to support")).toBeVisible();
  expect(screen.getByRole("heading", { name: "Tools available" })).toBeVisible();
  expect(screen.getByText("update_variables")).toBeVisible();
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

test("Metrics keeps measurement explanations in a tooltip", async () => {
  render(
    <CallConsole
      client={createFixtureClient("conversation")}
      initialTab="metrics"
    />,
  );

  expect(
    screen.queryByText("Final transcript received after input audio ended"),
  ).not.toBeInTheDocument();
  fireEvent.focus(
    screen.getByRole("button", { name: "Explain Final transcript latency" }),
  );
  expect(await screen.findByRole("tooltip")).toHaveTextContent(
    "Final transcript received after input audio ended",
  );
  expect(screen.queryByText("Remote playback")).not.toBeInTheDocument();
});

test("a message time exposes its correlated turn metrics on focus", async () => {
  render(<CallConsole client={createFixtureClient("conversation")} />);

  fireEvent.focus(
    screen.getByRole("button", {
      name: "View metrics for Assistant at 00:10",
    }),
  );

  expect(await screen.findByRole("tooltip")).toHaveTextContent("TTFT284 ms");
  expect(screen.getByRole("tooltip")).toHaveTextContent("Time to first audio88 ms");
  expect(screen.queryByRole("heading", { name: "Turn" })).not.toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "LLM" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "TTS" })).toBeVisible();
});

test("completed turns show final metrics only with authoritative inputs", async () => {
  render(<CallConsole client={createFixtureClient("conversation")} />);

  const completedTurn = screen
    .getByText(/Hi! I can help you arrange a delivery/)
    .closest("article");
  expect(completedTurn).not.toBeNull();
  const completedMetrics = within(completedTurn!).getByRole("button", {
    name: "View metrics for Assistant at 00:02",
  });
  fireEvent.focus(completedMetrics);
  expect(await screen.findByRole("tooltip")).toHaveTextContent(
    "Turn duration3,240 ms",
  );
  expect(screen.getByRole("tooltip")).toHaveTextContent("TPOT28 ms");
  expect(screen.getByRole("tooltip")).toHaveTextContent("RTF0.72 ×");
  fireEvent.blur(completedMetrics);

  const callerTurn = screen
    .getByText("I'd like to reschedule my delivery.")
    .closest("article");
  expect(callerTurn).not.toBeNull();
  expect(
    within(callerTurn!).getByRole("button", {
      name: "Metrics unavailable for You at 00:08",
    }),
  ).toBeDisabled();

  const streamingTurn = screen
    .getByText(/Of course. Let's find a time/)
    .closest("article");
  expect(streamingTurn).not.toBeNull();
  const streaming = within(streamingTurn!).getByRole("img", {
    name: "Streaming",
  });
  const metrics = within(streamingTurn!).getByRole("button", {
    name: "View metrics for Assistant at 00:10",
  });
  const time = within(streamingTurn!).getByText("00:10");

  expect(
    streaming.compareDocumentPosition(metrics) & Node.DOCUMENT_POSITION_FOLLOWING,
  ).toBeTruthy();
  expect(
    metrics.compareDocumentPosition(time) & Node.DOCUMENT_POSITION_FOLLOWING,
  ).toBeTruthy();
});
