import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { McpServicesStory } from "./McpServicesStory";

afterEach(() => {
  cleanup();
  window.history.replaceState({}, "", "/");
  vi.restoreAllMocks();
});

test("editing an existing MCP preserves the directory filter and focus", () => {
  render(<McpServicesStory scenario="directory-calendar" />);
  fireEvent.change(screen.getByRole("searchbox"), { target: { value: "Cal.com" } });
  const edit = screen.getByRole("button", { name: "Edit Cal.com" });
  fireEvent.click(edit);
  const dialog = within(screen.getByRole("dialog", { name: "Cal.com" }));
  fireEvent.click(dialog.getByRole("button", { name: "Close" }));
  expect(edit).toHaveFocus();
  expect(screen.getByRole("searchbox")).toHaveValue("Cal.com");
});

test("an existing telephony service opens its editor", () => {
  render(<McpServicesStory scenario="directory-telephony" />);
  fireEvent.click(screen.getByRole("button", { name: "Edit Telnyx" }));
  expect(screen.getByRole("dialog", { name: "Manage Telnyx" })).toBeVisible();
});

test("an invalid submission focuses its error so long forms reveal the recovery", () => {
  render(<McpServicesStory scenario="custom-oauth" />);
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  expect(screen.getByRole("alert")).toHaveTextContent(
    "Enter your OAuth client ID.",
  );
  expect(screen.getByRole("alert")).toHaveFocus();
});

test("the directory starts with AI models and groups integrations by their purpose", () => {
  render(<McpServicesStory scenario="picker" />);
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  const navigation = within(
    screen.getByRole("navigation", { name: "Integration categories" }),
  );
  expect(
    navigation
      .getAllByRole("link")
      .map((button) => button.textContent?.replace(/\d+$/, "")),
  ).toEqual(["Connected integrations", "AI models", "Telephony", "Calendar", "CRM", "Office suite"]);
  expect(
    screen.getByRole("button", { name: "Edit Deepgram" }),
  ).toBeVisible();
  for (const [category, names] of [
    ["Calendar", ["Cal.com", "Google Calendar", "Calendly"]],
    ["CRM", ["HubSpot"]],
    ["Office suite", ["Google Sheets", "Google Docs"]],
  ] as const) {
    fireEvent.click(
      navigation.getByRole("link", { name: new RegExp(category) }),
    );
    for (const name of names)
      expect(
        screen.getByRole("button", { name: `${["Cal.com", "HubSpot"].includes(name) ? "Edit" : "Connect"} ${name}` }),
      ).toBeVisible();
    expect(
      screen.queryByRole("button", { name: "Edit Deepgram" }),
    ).not.toBeInTheDocument();
  }
});

test("the page-level custom MCP action remains available with any category or search", () => {
  render(<McpServicesStory scenario="picker" />);
  fireEvent.change(screen.getByRole("searchbox"), {
    target: { value: "unlisted server" },
  });
  const action = screen.getByRole("button", { name: "Connect other MCP" });
  expect(action).toBeVisible();
  fireEvent.click(action);
  expect(
    screen.getByRole("dialog", { name: "Connect other MCP" }),
  ).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(action).toHaveFocus();
  expect(screen.getByRole("searchbox")).toHaveValue("unlisted server");
});

test("directory categories filter services and mobile category selection shares the same state", () => {
  render(<McpServicesStory scenario="picker" />);
  fireEvent.click(
    within(
      screen.getByRole("navigation", { name: "Integration categories" }),
    ).getByRole("link", { name: /Telephony/ }),
  );
  expect(screen.getByRole("button", { name: "Connect Twilio" })).toBeVisible();
  expect(
    screen.queryByRole("button", { name: "Connect Cal.com" }),
  ).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("Category"), {
    target: { value: "ai" },
  });
  expect(screen.getByRole("button", { name: "Connect OpenAI" })).toBeVisible();
  expect(
    screen.queryByRole("button", { name: "Connect Twilio" }),
  ).not.toBeInTheDocument();
});

test("an inherited service offers a tenant override from Edit", () => {
  render(<McpServicesStory scenario="picker" />);
  fireEvent.click(screen.getByRole("button", { name: "Edit Deepgram" }));
  fireEvent.click(screen.getByRole("button", { name: "Override for this tenant" }));
  expect(screen.getByRole("dialog", { name: "Connect Deepgram" })).toBeVisible();
  expect(screen.getByLabelText("API key")).toBeVisible();
});

test.each(["OpenAI", "Google AI Studio"])(
  "%s opens a fixed-provider modal and cancel preserves directory search",
  (name) => {
    render(<McpServicesStory scenario="picker" />);
    fireEvent.change(screen.getByRole("searchbox"), {
      target: { value: name },
    });
    fireEvent.click(screen.getByRole("button", { name: `Connect ${name}` }));
    const dialog = within(
      screen.getByRole("dialog", { name: `Connect ${name}` }),
    );
    expect(dialog.queryByRole("combobox")).not.toBeInTheDocument();
    expect(dialog.getByLabelText("API key")).toHaveAttribute(
      "type",
      "password",
    );
    fireEvent.click(dialog.getByRole("button", { name: "Cancel" }));
    expect(screen.getByRole("searchbox")).toHaveValue(name);
    expect(
      screen.getByRole("button", { name: `Connect ${name}` }),
    ).toHaveFocus();
  },
);

test("telephony credentials and simulated save keep the selected provider", async () => {
  const fetch = vi.spyOn(window, "fetch");
  render(<McpServicesStory scenario="picker" />);
  fireEvent.change(screen.getByLabelText("Category"), {
    target: { value: "telephony" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Connect Twilio" }));
  fireEvent.change(screen.getByLabelText("Account SID"), {
    target: { value: "AC" + "1".repeat(32) },
  });
  fireEvent.change(screen.getByLabelText("Auth token"), {
    target: { value: "sample-token" },
  });
  fireEvent.click(
    within(screen.getByRole("dialog")).getByRole("button", { name: "Connect" }),
  );
  await screen.findByRole("button", { name: "Manage Twilio" });
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "ai" } });
  fireEvent.change(screen.getByLabelText("Category"), { target: { value: "telephony" } });
  fireEvent.click(screen.getByRole("button", { name: "Edit Twilio" }));
  expect(screen.getByRole("dialog", { name: "Manage Twilio" })).toBeVisible();
  expect(fetch).not.toHaveBeenCalled();
});

test("a custom anonymous connection keeps its endpoint path and never makes a network request", async () => {
  const fetch = vi.spyOn(window, "fetch");
  render(<McpServicesStory scenario="custom" />);
  expect(screen.queryByLabelText("Connection name")).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("MCP server URL"), {
    target: { value: "https://directory.example.test/team/mcp" },
  });
  fireEvent.change(screen.getByLabelText("Authentication"), {
    target: { value: "none" },
  });
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await screen.findByText("Connection ready");
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  expect(
    screen.getByRole("button", { name: "Manage Office tools" }),
  ).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: "Manage Office tools" }),
  );
  expect(
    screen.getByLabelText("MCP server URL"),
  ).toHaveValue("https://directory.example.test/team/mcp");
  expect(fetch).not.toHaveBeenCalled();
});

test("manual OAuth exposes endpoints, client authentication and additional parameters", () => {
  render(<McpServicesStory scenario="custom-oauth" />);
  expect(screen.getByLabelText("Client ID")).toBeVisible();
  expect(screen.getByLabelText("Client secret")).toHaveAttribute(
    "type",
    "password",
  );
  fireEvent.click(
    screen.getByRole("button", { name: /OAuth endpoints and scopes/ }),
  );
  fireEvent.change(screen.getByLabelText("Endpoint configuration"), {
    target: { value: "manual" },
  });
  expect(screen.getByLabelText("Authorization URL")).toBeVisible();
  expect(screen.getByLabelText("Token URL")).toBeVisible();
  expect(screen.getByLabelText("Scopes")).toBeVisible();
  fireEvent.click(
    screen.getByRole("button", { name: /Additional parameters/ }),
  );
  fireEvent.click(
    screen.getByRole("button", { name: "Add authorization parameter" }),
  );
  expect(screen.getByLabelText("Authorization parameter name 1")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Add token parameter" }));
  expect(screen.getByLabelText("Token parameter value 1")).toHaveAttribute(
    "type",
    "password",
  );
});

test("custom header auth supports adding and removing masked credentials", () => {
  render(<McpServicesStory scenario="custom-headers" />);
  expect(screen.getByLabelText("Header name 1")).toHaveValue("X-API-Key");
  expect(screen.getByLabelText("Header value 1")).toHaveAttribute(
    "type",
    "password",
  );
  fireEvent.click(screen.getByRole("button", { name: "Add header" }));
  expect(screen.getByLabelText("Header name 2")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Remove header 2" }));
  expect(screen.queryByLabelText("Header name 2")).not.toBeInTheDocument();
});

test("a signing key stays masked until explicitly revealed for multiline editing", () => {
  render(<McpServicesStory scenario="custom-oauth" />);
  fireEvent.change(screen.getByLabelText("Client authentication"), {
    target: { value: "private_key_jwt" },
  });
  expect(screen.getByLabelText("Private key (PEM)")).toHaveAttribute(
    "type",
    "password",
  );
  fireEvent.click(
    screen.getByRole("button", { name: "Show private key (pem)" }),
  );
  expect(screen.getByLabelText("Private key (PEM)").tagName).toBe("TEXTAREA");
});

test("OAuth cancellation retains the directory MCP identity without editable setup fields", async () => {
  render(<McpServicesStory scenario="calcom" />);
  fireEvent.click(screen.getByRole("button", { name: "Connect" }));
  await screen.findByRole("button", { name: "Simulate authorization" });
  fireEvent.click(screen.getByRole("button", { name: "Cancel authorization" }));
  expect(screen.getByRole("dialog", { name: "Connect Cal.com" })).toBeVisible();
  expect(screen.queryByLabelText("Connection name")).not.toBeInTheDocument();
  expect(screen.getByRole("alert")).toHaveTextContent("Authorization canceled");
});

test("reconnect and disconnect operate only on the selected tenant connection", async () => {
  render(<McpServicesStory scenario="reconnect" />);
  fireEvent.click(screen.getByRole("button", { name: "Reconnect" }));
  fireEvent.click(
    await screen.findByRole("button", { name: "Simulate authorization" }),
  );
  await screen.findByText("Connection ready");
  fireEvent.click(screen.getByRole("button", { name: "Done" }));
  fireEvent.click(
    screen.getByRole("button", { name: "Manage Cal.com" }),
  );
  fireEvent.click(screen.getByRole("button", { name: "Disconnect" }));
  fireEvent.click(screen.getByRole("button", { name: "Disconnect MCP" }));
  await waitFor(() =>
    expect(
      screen.queryByRole("button", { name: "Manage Cal.com" }),
    ).not.toBeInTheDocument(),
  );
  expect(
    screen.getByRole("button", { name: "Manage HubSpot" }),
  ).toBeVisible();
});
