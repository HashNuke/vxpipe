import {
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { expect, test } from "vitest";
import { CallConsole } from "../src/index.js";
import { createFixtureController } from "../stories/fixtureClient.js";

test("the host can bound the console height", () => {
  const { container } = render(
    <CallConsole
      controller={createFixtureController("conversation")}
      maxHeight="640px"
    />,
  );

  expect(container.firstElementChild).toHaveStyle({ maxHeight: "640px" });
});

test("the host can inject call context before the compact call controls", () => {
  render(
    <CallConsole
      controller={createFixtureController("conversation")}
      headerContext={<code>call-018f</code>}
    />,
  );

  const context = screen.getByText("call-018f");
  const status = screen.getByText("Connected");
  const input = screen.getByRole("button", {
    name: "Input device: Built-in microphone",
  });

  expect(context).toBeVisible();
  expect(context.compareDocumentPosition(status)).toBe(
    Node.DOCUMENT_POSITION_FOLLOWING,
  );
  expect(status.compareDocumentPosition(input)).toBe(
    Node.DOCUMENT_POSITION_FOLLOWING,
  );
});

test("the host can inject a dedicated header row and fill its container", () => {
  const { container } = render(
    <CallConsole
      controller={createFixtureController("conversation")}
      header={<nav aria-label="Call breadcrumb">Tenant / Calls / Call details</nav>}
      headerVisibility="desktop"
      layout="fill"
    />,
  );

  const consoleRoot = container.firstElementChild;
  const breadcrumb = screen.getByRole("navigation", { name: "Call breadcrumb" });
  const controls = screen.getByText("Connected").closest("header");

  expect(consoleRoot).toHaveClass("vx-console-fill");
  expect(breadcrumb.parentElement).toHaveClass(
    "vx-console-header",
    "vx-console-header-desktop",
  );
  expect(
    breadcrumb.compareDocumentPosition(controls as Node) &
      Node.DOCUMENT_POSITION_FOLLOWING,
  ).toBeTruthy();
});

test("a denied microphone still allows typed input in the same conversation", async () => {
  const client = createFixtureController("microphone-denied");
  render(<CallConsole controller={client} />);
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

test("microphone denial does not block starting a text-only call", async () => {
  const client = createFixtureController("microphone-denied-ready");
  render(<CallConsole controller={client} />);

  expect(
    screen.getByText("Microphone access is blocked. You can still type."),
  ).toBeVisible();
  expect(
    screen.getByRole("button", { name: "Enable microphone" }),
  ).toBeDisabled();
  expect(
    screen.getByRole("button", { name: /Input device:/ }),
  ).toBeDisabled();
  expect(screen.getByRole("button", { name: "Start call" })).toBeEnabled();

  fireEvent.click(screen.getByRole("button", { name: "Start call" }));
  await waitFor(() => expect(screen.getByText("Connected")).toBeVisible());
  expect(screen.getByRole("textbox", { name: "Message" })).toBeEnabled();
  expect(
    screen.getByRole("button", { name: "Enable microphone" }),
  ).toBeDisabled();
});

test("leaving keeps the transcript visible and disables further sending", async () => {
  const client = createFixtureController("conversation");
  render(<CallConsole controller={client} />);
  fireEvent.click(screen.getByRole("button", { name: "Show Logs" }));
  expect(screen.getByText("client-ready")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Leave call" }));
  await waitFor(() => expect(screen.getByText("Call ended")).toBeVisible());
  expect(screen.getByText("I'd like to reschedule my delivery.")).toBeVisible();
  expect(screen.getByRole("button", { name: "Send message" })).toBeDisabled();

  fireEvent.click(screen.getByRole("button", { name: "Call" }));
  await waitFor(() => expect(screen.getByText("Connected")).toBeVisible());
  expect(screen.queryByText("client-ready")).not.toBeInTheDocument();
  expect(screen.queryByText(/You left the call/)).not.toBeInTheDocument();
  await waitFor(() =>
    expect(screen.getByRole("textbox", { name: "Message" })).toBeEnabled(),
  );
});

test("Conversation filters messages, events, tool calls and raw RTVI logs", () => {
  render(<CallConsole controller={createFixtureController("human-handoff")} />);

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
  render(<CallConsole controller={createFixtureController("tool-states")} />);

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
  const completedTool = disclosure.closest(".vx-timeline-tool") as HTMLElement;
  const completedDetails = within(completedTool);
  expect(completedDetails.getByRole("tab", { name: "Request" })).toHaveAttribute(
    "aria-selected",
    "true",
  );
  const completedResponseTab = completedDetails.getByRole("tab", {
    name: "Response",
  });
  expect(within(completedResponseTab).getByText("200")).toBeVisible();
  expect(
    completedDetails.getByText(/"requested_date": "2026-09-18"/),
  ).toBeVisible();
  fireEvent.click(completedResponseTab);
  expect(
    within(completedDetails.getByRole("tabpanel")).queryByText("HTTP 200"),
  ).not.toBeInTheDocument();
  expect(completedDetails.getByText(/"updated": true/)).toBeVisible();

  fireEvent.click(
    screen.getByRole("button", {
      name: "Hide details for update_variables",
    }),
  );

  const failedDisclosure = screen.getByRole("button", {
    name: "Show details for notify_customer",
  });
  fireEvent.click(failedDisclosure);
  const failedDetails = within(
    failedDisclosure.closest(".vx-timeline-tool") as HTMLElement,
  );
  const failedResponseTab = failedDetails.getByRole("tab", { name: "Response" });
  expect(within(failedResponseTab).getByText("503")).toBeVisible();
  fireEvent.click(failedResponseTab);
  expect(failedDetails.getByText(/"error": "Service unavailable"/)).toBeVisible();

  const emptyDisclosure = screen.getByRole("button", {
    name: "Show details for refresh_cache",
  });
  fireEvent.click(emptyDisclosure);
  const emptyDetails = within(
    emptyDisclosure.closest(".vx-timeline-tool") as HTMLElement,
  );
  expect(emptyDetails.getByText("No request arguments.")).toBeVisible();
  const emptyResponseTab = emptyDetails.getByRole("tab", { name: "Response" });
  expect(within(emptyResponseTab).getByText("204")).toBeVisible();
  fireEvent.click(emptyResponseTab);
  expect(emptyDetails.getByText("No response body.")).toBeVisible();
});

test("speaking activity moves to the participant avatar", () => {
  render(<CallConsole controller={createFixtureController("no-alignment")} />);

  const assistant = screen.getByRole("button", {
    name: "View Assistant details",
  });
  expect(assistant).toHaveTextContent("connected");
  expect(assistant).not.toHaveTextContent("speaking");
  expect(
    within(assistant).getByLabelText("Assistant is speaking"),
  ).toBeVisible();
  expect(screen.queryByText("Assistant is speaking")).not.toBeInTheDocument();
  expect(document.querySelector("mark")).toBeNull();
});

test("device menus expose styled options and apply the selected device", async () => {
  const client = createFixtureController("conversation");
  render(<CallConsole controller={client} />);

  fireEvent.click(
    screen.getByRole("button", { name: "Input device: Built-in microphone" }),
  );
  const current = await screen.findByRole("menuitemradio", {
    name: "Built-in microphone",
  });
  const headset = screen.getByRole("menuitemradio", { name: "USB headset" });

  await waitFor(() => expect(current).toHaveFocus());
  fireEvent.keyDown(current, { key: "ArrowDown" });
  expect(headset).toHaveFocus();
  fireEvent.click(headset);

  await waitFor(() =>
    expect(client.getSnapshot().inputDevice).toBe("USB headset"),
  );
  expect(
    screen.getByRole("button", { name: "Input device: USB headset" }),
  ).toBeVisible();
});

test("Variables displays the latest authorized snapshot by section", () => {
  render(
    <CallConsole
      controller={createFixtureController("conversation")}
      initialTab="variables"
    />,
  );

  expect(screen.getByRole("heading", { name: "intake" })).toBeVisible();
  expect(screen.getByText("requested_date")).toBeVisible();
  expect(screen.getByText("2026-09-18")).toBeVisible();
});

test("configured participants remain in the sidebar before joining", () => {
  render(<CallConsole controller={createFixtureController("ready")} />);

  const caller = screen.getByRole("button", { name: "View Caller details" });
  expect(caller).toHaveTextContent("WebRTC");
  expect(caller).not.toHaveTextContent("inactive");
  expect(within(caller).getByLabelText("WebRTC, inactive")).toBeVisible();
  expect(caller).not.toHaveTextContent("Browser participant");

  const assistant = screen.getByRole("button", {
    name: "View Assistant details",
  });
  expect(assistant).toHaveTextContent("inactive");
  expect(assistant).not.toHaveTextContent("Delivery concierge");

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

test("a phone caller displays its E.164 number without repeating connection state", () => {
  render(<CallConsole controller={createFixtureController("phone-caller")} />);

  const caller = screen.getByRole("button", { name: "View Caller details" });
  expect(caller).toHaveTextContent("+14155550123");
  expect(caller).not.toHaveTextContent("connected");
  expect(
    within(caller).getByLabelText("+14155550123, connected"),
  ).toBeVisible();
});

test("a connected non-caller displays its connection method", () => {
  render(<CallConsole controller={createFixtureController("human-handoff")} />);

  const support = screen.getByRole("button", {
    name: "View Support teammate details",
  });
  expect(support).toHaveTextContent("WebRTC");
  expect(support).not.toHaveTextContent("connected");
  expect(within(support).getByLabelText("WebRTC, connected")).toBeVisible();
});

test("a transferred human keeps connection media separate from configured capabilities", () => {
  render(<CallConsole controller={createFixtureController("human-handoff")} />);

  fireEvent.click(
    screen.getByRole("button", { name: "View Support teammate details" }),
  );

  const details = screen.getByRole("region", { name: "Participant details" });
  expect(within(details).getByText("Speech to text")).toBeVisible();
  expect(within(details).getByText("Deepgram")).toBeVisible();
  expect(within(details).queryByText("Voice")).not.toBeInTheDocument();
  expect(within(details).queryByText("WebRTC")).not.toBeInTheDocument();
});

test("a sidebar participant opens their authorized configuration", () => {
  render(<CallConsole controller={createFixtureController("conversation")} />);

  const tabs = within(screen.getByRole("navigation", { name: "Call views" }))
    .getAllByRole("button")
    .map((button) => button.textContent)
    .filter((label) => label !== "");
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
  expect(screen.queryByText("Delivery concierge")).not.toBeInTheDocument();
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

test("a conversation participant identity opens their details", () => {
  render(<CallConsole controller={createFixtureController("conversation")} />);

  fireEvent.click(
    screen.getAllByRole("button", { name: "Open Assistant participant" }).at(-1)!,
  );

  const participantsTab = screen.getByRole("button", { name: "Participants" });
  expect(participantsTab).toHaveAttribute(
    "aria-current",
    "page",
  );
  expect(participantsTab).toHaveFocus();
  expect(screen.getByRole("heading", { name: "Assistant" })).toBeVisible();
  expect(
    screen.getByRole("navigation", { name: "Select participant" }),
  ).toBeVisible();
});

test("the Participants view can select another participant without the sidebar", () => {
  render(
    <CallConsole
      controller={createFixtureController("human-handoff")}
      initialTab="participants"
    />,
  );

  const picker = screen.getByRole("navigation", { name: "Select participant" });
  fireEvent.click(
    within(picker).getByRole("button", { name: "View Support teammate details" }),
  );

  expect(screen.getByRole("heading", { name: "Support teammate" })).toBeVisible();
});

test("Metrics presents every scope in one measurement table", () => {
  render(
    <CallConsole
      controller={createFixtureController("conversation")}
      initialTab="metrics"
    />,
  );

  const table = screen.getByRole("table", { name: "Call metrics" });
  expect(within(table).getByRole("columnheader", { name: "Target" })).toBeVisible();
  expect(
    within(table).getByRole("columnheader", { name: "Call duration" }),
  ).toBeVisible();
  expect(
    within(table).getByRole("columnheader", { name: "Input tokens" }),
  ).toBeVisible();
  expect(
    within(table).getByRole("rowheader", { name: "Room capability: STT" }),
  ).toBeVisible();
  expect(
    within(table).getByRole("rowheader", { name: "Participant: Caller" }),
  ).toBeVisible();
  const llm = within(table).getByRole("rowheader", {
    name: "LLM, Assistant",
  });
  expect(llm).toHaveTextContent("LLM");
  expect(within(llm).getByText("Assistant")).toHaveClass(
    "vx-metric-participant-badge",
  );
  expect(llm).not.toHaveTextContent("Participant capability");
});

test("Metrics keeps source and measurement context in a cell tooltip", async () => {
  render(
    <CallConsole
      controller={createFixtureController("conversation")}
      initialTab="metrics"
    />,
  );

  expect(
    screen.queryByText("Final transcript received after input audio ended"),
  ).not.toBeInTheDocument();
  fireEvent.focus(screen.getByRole("button", {
    name: "Final transcript latency for Room capability: STT: 184 ms",
  }));
  const tooltip = await screen.findByRole("tooltip");
  expect(tooltip).toHaveTextContent("Final transcript received after input audio ended");
  expect(tooltip).toHaveTextContent("STT · 1 turn");
  expect(screen.queryByText("Remote playback")).not.toBeInTheDocument();
});

test("Metrics expands compact column labels in a tooltip", async () => {
  render(
    <CallConsole
      controller={createFixtureController("conversation")}
      initialTab="metrics"
    />,
  );

  expect(screen.getByRole("columnheader", { name: "Call duration" })).toHaveTextContent(
    "DUR",
  );
  expect(screen.getByRole("columnheader", { name: "Input tokens" })).toHaveTextContent(
    "Input",
  );
  fireEvent.focus(
    screen.getByRole("button", { name: "Explain Input tokens" }),
  );
  expect(await screen.findByRole("tooltip")).toHaveTextContent("Input tokens");
});

test("a message time exposes its correlated turn metrics on focus", async () => {
  render(<CallConsole controller={createFixtureController("conversation")} />);

  fireEvent.focus(
    screen.getAllByRole("button", {
      name: /View metrics for Assistant at/,
    }).at(-1)!,
  );

  expect(await screen.findByRole("tooltip")).toHaveTextContent("TTFT284 ms");
  expect(screen.getByRole("tooltip")).toHaveTextContent("Time to first audio88 ms");
  expect(screen.queryByRole("heading", { name: "Turn" })).not.toBeInTheDocument();
  expect(screen.getByRole("heading", { name: "LLM" })).toBeVisible();
  expect(screen.getByRole("heading", { name: "TTS" })).toBeVisible();
});

test("timeline times show local clock time and disclose the UTC instant", async () => {
  const { container } = render(
    <CallConsole controller={createFixtureController("conversation")} />,
  );

  const timestamp = container.querySelector(
    'time[datetime="2026-09-16T22:30:00.000Z"]',
  );
  expect(timestamp).not.toBeNull();
  expect(timestamp).not.toHaveTextContent("00:00");

  fireEvent.focus(timestamp as HTMLElement);
  const tooltip = await screen.findByRole("tooltip");
  expect(tooltip).toHaveTextContent("2026-09-16T22:30:00.000Z");
  expect(tooltip).toHaveTextContent(
    Intl.DateTimeFormat().resolvedOptions().timeZone,
  );
});

test("completed turns show final metrics only with authoritative inputs", async () => {
  render(<CallConsole controller={createFixtureController("conversation")} />);

  const completedTurn = screen
    .getByText(/Hi! I can help you arrange a delivery/)
    .closest("article");
  expect(completedTurn).not.toBeNull();
  const completedMetrics = within(completedTurn!).getByRole("button", {
    name: /View metrics for Assistant at/,
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
      name: /Metrics unavailable for You at/,
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
    name: /View metrics for Assistant at/,
  });
  const time = streamingTurn!.querySelector("time");
  expect(time).not.toBeNull();

  expect(
    streaming.compareDocumentPosition(metrics) & Node.DOCUMENT_POSITION_FOLLOWING,
  ).toBeTruthy();
  expect(
    metrics.compareDocumentPosition(time!) & Node.DOCUMENT_POSITION_FOLLOWING,
  ).toBeTruthy();
});
