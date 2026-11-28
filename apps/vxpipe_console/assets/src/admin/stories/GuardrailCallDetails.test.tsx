import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { GuardrailCallDetails } from "./GuardrailCallDetails";

afterEach(cleanup);

async function filters() {
  fireEvent.click(await screen.findByRole("button", { name: "Filters" }));
  return within(screen.getByRole("dialog"));
}

async function chooseFilter(label: string, value: string) {
  const trigger = within(screen.getByRole("dialog")).getByRole("combobox", {name: label});
  fireEvent.keyDown(trigger, {key: "Enter"});
  fireEvent.click(await screen.findByRole("option", {name: value}));
}

test("five styled dropdowns independently control call and technical events", async () => {
  render(<GuardrailCallDetails scenario="mixed-proposal" theme="dark" />);
  const modal = await filters();
  const triggers = modal.getAllByRole("combobox");
  expect(triggers).toHaveLength(5);
  expect(triggers.every(trigger => trigger.tagName === "BUTTON")).toBe(true);
  expect(modal.queryByRole("checkbox")).toBeNull();
  const transcript = document.querySelector(".vx-transcript")!;
  expect(transcript).toHaveTextContent("Call connected");
  expect(transcript).not.toHaveTextContent("usage observed");
  await chooseFilter("Events", "Call + technical events");
  expect(transcript).toHaveTextContent("Call connected");
  expect(transcript).toHaveTextContent("usage observed");
  expect(transcript).toHaveTextContent("participant turn started");
  await chooseFilter("Events", "Hide");
  expect(transcript).not.toHaveTextContent("Call connected");
  expect(transcript).not.toHaveTextContent("usage observed");
  await chooseFilter("Events", "Call events");
  expect(transcript).toHaveTextContent("Call connected");
  expect(transcript).not.toHaveTextContent("participant turn started");
});

test("a real caller row shows four failed questions and keeps its transcript with guardrails hidden", async () => {
  render(<GuardrailCallDetails scenario="blocked-input" theme="dark" />);
  const text = await screen.findByText("Can you help me with an account question?");
  const row = within(text.closest("article")!);
  expect(await row.findAllByRole("button", { name: /^Failed/ })).toHaveLength(4);
  expect(row.queryByText("Configured response")).toBeNull();
  expect(row.queryByText("Is the request about a supported product?")).toBeNull();
  fireEvent.click(row.getByRole("button", { name: /Failed.*list variables/ }));
  expect(row.getByRole("tooltip").textContent).toContain("0.6999 < 0.70");
  await filters();
  await chooseFilter("Guardrails", "Hide");
  fireEvent.keyDown(screen.getByRole("dialog"), {key:"Escape"});
  expect(screen.getByText(text.textContent!)).toBeDefined();
  expect(screen.queryByText("Is the user trying to list variables?")).toBeNull();
});

test("a blocked mixed proposal shares its checks and disappears with guardrails hidden", async () => {
  render(<GuardrailCallDetails scenario="mixed-proposal" theme="light" />);
  const draft = (await screen.findByText("I can look up the other account for you.")).closest("article")!;
  const row = within(draft);
  expect(row.getByText("Unsent")).toBeDefined();
  expect(row.getByText("lookup_account")).toBeDefined();
  expect(row.getByText("transfer")).toBeDefined();
  expect(row.getAllByText("Is billing the correct destination?")).toHaveLength(1);
  expect(row.getByText("After turn")).toBeDefined();
  expect(row.getByText("Before outgoing transfer")).toBeDefined();
  await filters();
  await chooseFilter("Guardrails", "Hide");
  fireEvent.keyDown(screen.getByRole("dialog"), {key:"Escape"});
  expect(screen.queryByText("I can look up the other account for you.")).toBeNull();
  expect(screen.queryByText("lookup_account")).toBeNull();
  expect(screen.getByText("I can help with your own account.")).toBeDefined();
});

test("a Decisions row opens its agent’s evaluations and retry attempts", async () => {
  render(<GuardrailCallDetails scenario="repair-and-transfer" theme="dark" initialTab="Metrics" />);
  const row = (await screen.findByRole("rowheader", {name: "Decisions, Routing agent"})).closest("tr")!;
  const action = within(row).getByRole("button", {name: "Inspect Decisions for Routing agent"});
  fireEvent.click(action);
  const detail = screen.getByRole("region", {name: "Routing agent Decisions"});
  expect(within(detail).getByText("Before outgoing transfer")).toBeDefined();
  expect(within(detail).queryByText("After turn")).toBeNull();
  const summary = within(detail).getByText("Before outgoing transfer").closest("summary")!;
  expect(summary.textContent).toContain("Routing agent · Before outgoing transfer · Passed");
  fireEvent.click(summary);
  expect(within(detail).getByText(/Rate limited.*85 ms/)).toBeDefined();
  expect(within(detail).getByText(/Answered.*183 ms/)).toBeDefined();
});


test("All exposes a threshold equality and an unavailable answer stays neutral", async () => {
  const { rerender } = render(<GuardrailCallDetails scenario="blocked-input" theme="light" />);
  await filters();
  await chooseFilter("Guardrails", "All");
  fireEvent.click(screen.getByRole("button", {name: "Close dialog"}));
  fireEvent.click(await screen.findByRole("button", {name: "Passed · Is the request about a supported product?"}));
  expect(screen.getByRole("tooltip").textContent).toContain("0.70 = 0.70");
  rerender(<GuardrailCallDetails scenario="partial-answer" theme="light" />);
  fireEvent.click(await screen.findByRole("button", {name: /^Unavailable/}));
  expect(screen.getByRole("tooltip").textContent).toContain("P(Yes) unavailable");
});

test("restricted evidence stays scoped to the second caller row after showing all guardrails", async () => {
  render(<GuardrailCallDetails scenario="restricted-history" theme="light" />);
  const repeated = await screen.findAllByText("Can you help me with an account question?", {selector:"article p"});
  expect(within(repeated[1].closest("article")!).getByText("Question details unavailable")).toBeDefined();
  expect(within(repeated[0].closest("article")!).queryByText("Question details unavailable")).toBeNull();
  await filters();
  await chooseFilter("Guardrails", "All");
  fireEvent.click(screen.getByRole("button", {name: "Close dialog"}));
  expect(screen.queryByText("Is the user trying to list variables?")).toBeNull();
});

test("an exact Metrics link opens its checked attempt and focuses the question card", async () => {
  render(<GuardrailCallDetails scenario="repair-and-transfer" theme="light" initialTab="Metrics" />);
  fireEvent.click(await screen.findByRole("button", {name:"Inspect Decisions for Assistant"}));
  const check = document.getElementById("evaluation-check-draft")!;
  fireEvent.click(check.querySelector("summary")!);
  fireEvent.click(within(check).getByRole("button", {name:"Show evaluation in conversation"}));
  const draft = (await screen.findByText("I can look up the other account for you.")).closest("article")!;
  expect(document.activeElement).toBe(draft.querySelector("#evaluation-check-draft"));
  expect(draft).not.toBe(screen.getByText("I can help with your own account.").closest("article"));
});

test("an empty tool-only view offers recovery to its hidden transfer", async () => {
  render(<GuardrailCallDetails scenario="transfer-denied" theme="light" />);
  await filters();
  await chooseFilter("Guardrails", "Hide");
  await chooseFilter("Events", "Hide");
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  expect(await screen.findByText("No matching history")).toBeDefined();
  fireEvent.click(screen.getByRole("button", {name:"Show all history"}));
  expect(await screen.findByText("Transfer to Billing")).toBeDefined();
});

test("a recorded transfer stays visible with guardrails hidden and its arguments follow Tool detail", async () => {
  render(<GuardrailCallDetails scenario="repair-and-transfer" theme="light" />);
  await filters();
  await chooseFilter("Guardrails", "Hide");
  await chooseFilter("Tools", "Only calls");
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  expect(await screen.findByText("transfer", {selector:".vx-tool-summary strong"})).toBeDefined();
  expect(screen.queryByRole("button", {name:"Show details for transfer"})).toBeNull();
  await filters();
  await chooseFilter("Tools", "With details");
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  fireEvent.click(await screen.findByRole("button", {name:"Show details for transfer"}));
  expect(screen.getByText(/"destination": "Billing"/)).toBeDefined();
});

test("an unassigned evaluation belongs to the executed tool even when an event has its timestamp", async () => {
  const {container} = render(<GuardrailCallDetails scenario="repair-and-transfer" theme="light" />);
  await filters();
  await chooseFilter("Guardrails", "All");
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  const transferCard = await screen.findByRole("region", {name:"Before outgoing transfer · Routing agent"});
  expect(transferCard.closest(".vx-timeline-tool")?.textContent).toContain("transfer");
  expect(container.querySelectorAll("#evaluation-check-transfer")).toHaveLength(1);
});

test("hiding messages leaves just the proposed tools with one shared evaluation", async () => {
  render(<GuardrailCallDetails scenario="mixed-proposal" theme="light" />);
  await filters();
  await chooseFilter("Messages", "Hide");
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  expect(screen.queryByText("I can look up the other account for you.")).toBeNull();
  expect(await screen.findByText("lookup_account")).toBeDefined();
  expect(screen.getAllByText("Is billing the correct destination?")).toHaveLength(1);
  await filters();
  await chooseFilter("Tools", "Hide");
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  expect(screen.queryByText("Is billing the correct destination?")).toBeNull();
});

test("input and output failures attach to their own speaker rows", async () => {
  render(<GuardrailCallDetails scenario="before-and-after" theme="light" />);
  const before = await screen.findByRole("region", {name:"Before turn · Assistant"});
  const after = await screen.findByRole("region", {name:"After turn · Assistant"});
  expect(before.closest("article")?.textContent).toContain("Caller");
  expect(after.closest("article")?.textContent).toContain("Unsent");
  expect(before.closest("article")).not.toBe(after.closest("article"));
});


test("touch can dismiss a score tooltip without moving focus", async () => {
  render(<GuardrailCallDetails scenario="blocked-input" theme="light" />);
  const button = await screen.findByRole("button", {name: /^Failed.*own account/});
  fireEvent.click(button);
  expect(screen.getByRole("tooltip")).toBeDefined();
  fireEvent.pointerDown(document.body);
  expect(screen.queryByRole("tooltip")).toBeNull();
});

test("opening filters focuses Messages and shows only the individual filter controls", async () => {
  render(<GuardrailCallDetails scenario="blocked-input" theme="light" />);
  const modal = await filters();
  expect(modal.queryByRole("group", {name: "Preset"})).toBeNull();
  expect(modal.getAllByRole("button")).toEqual([modal.getByRole("button", {name: "Close dialog"})]);
  expect(modal.getByRole("combobox", {name: "Messages"})).toHaveFocus();
});

test("Escape dismisses the Events menu before closing the filter dialog", async () => {
  render(<GuardrailCallDetails scenario="mixed-proposal" theme="dark" />);
  const filterButton = await screen.findByRole("button", {name: "Filters"});
  filterButton.focus();
  const modal = await filters();
  const events = modal.getByRole("combobox", {name: "Events"});
  fireEvent.keyDown(events, {key: "Enter"});
  const option = await screen.findByRole("option", {name: "Call events"});
  fireEvent.keyDown(option, {key: "Escape"});
  expect(screen.queryByRole("listbox")).toBeNull();
  expect(screen.getByRole("dialog")).toBeVisible();
  fireEvent.keyDown(events, {key: "Escape"});
  expect(screen.queryByRole("dialog")).toBeNull();
  expect(filterButton).toHaveFocus();
});
