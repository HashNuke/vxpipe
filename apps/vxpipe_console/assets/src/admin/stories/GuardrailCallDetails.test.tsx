import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { GuardrailCallDetails } from "./GuardrailCallDetails";

afterEach(cleanup);

async function filters() {
  fireEvent.click(await screen.findByRole("button", { name: "Filters" }));
  return within(screen.getByRole("dialog"));
}

test("a real caller row shows four failed questions and keeps its transcript in Info", async () => {
  render(<GuardrailCallDetails scenario="blocked-input" theme="dark" />);
  const text = await screen.findByText("Can you help me with an account question?");
  const row = within(text.closest("article")!);
  expect(await row.findAllByRole("button", { name: /^Failed/ })).toHaveLength(4);
  expect(row.queryByText("Configured response")).toBeNull();
  expect(row.queryByText("Is the request about a supported product?")).toBeNull();
  fireEvent.click(row.getByRole("button", { name: /Failed.*list variables/ }));
  expect(row.getByRole("tooltip").textContent).toContain("0.6999 < 0.70");
  fireEvent.click((await filters()).getByRole("button", { name: "Info" }));
  fireEvent.keyDown(screen.getByRole("dialog"), {key:"Escape"});
  expect(screen.getByText(text.textContent!)).toBeDefined();
  expect(screen.queryByText("Is the user trying to list variables?")).toBeNull();
});

test("a blocked mixed proposal shares its checks and disappears in Info", async () => {
  render(<GuardrailCallDetails scenario="mixed-proposal" theme="light" />);
  const draft = (await screen.findByText("I can look up the other account for you.")).closest("article")!;
  const row = within(draft);
  expect(row.getByText("Unsent")).toBeDefined();
  expect(row.getByText("lookup_account")).toBeDefined();
  expect(row.getByText("transfer")).toBeDefined();
  expect(row.getAllByText("Is billing the correct destination?")).toHaveLength(1);
  expect(row.getByText("After turn")).toBeDefined();
  expect(row.getByText("Before outgoing transfer")).toBeDefined();
  fireEvent.click((await filters()).getByRole("button", { name: "Info" }));
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
  fireEvent.click((await filters()).getByRole("button", {name: "All"}));
  fireEvent.click(screen.getByRole("button", {name: "Close dialog"}));
  fireEvent.click(await screen.findByRole("button", {name: "Passed · Is the request about a supported product?"}));
  expect(screen.getByRole("tooltip").textContent).toContain("0.70 = 0.70");
  rerender(<GuardrailCallDetails scenario="partial-answer" theme="light" />);
  fireEvent.click(await screen.findByRole("button", {name: /^Unavailable/}));
  expect(screen.getByRole("tooltip").textContent).toContain("P(Yes) unavailable");
});

test("restricted evidence stays scoped to the second caller row after switching presets", async () => {
  render(<GuardrailCallDetails scenario="restricted-history" theme="light" />);
  const repeated = await screen.findAllByText("Can you help me with an account question?", {selector:"article p"});
  expect(within(repeated[1].closest("article")!).getByText("Question details unavailable")).toBeDefined();
  expect(within(repeated[0].closest("article")!).queryByText("Question details unavailable")).toBeNull();
  fireEvent.click((await filters()).getByRole("button", {name:"All"}));
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
  const modal = await filters();
  fireEvent.click(modal.getByRole("button", {name:"Info"}));
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  expect(await screen.findByText("No matching history")).toBeDefined();
  fireEvent.click(screen.getByRole("button", {name:"Show all history"}));
  expect(await screen.findByText("Transfer to Billing")).toBeDefined();
});

test("a recorded transfer stays visible in Info and its arguments follow Tool detail", async () => {
  render(<GuardrailCallDetails scenario="repair-and-transfer" theme="light" />);
  fireEvent.click((await filters()).getByRole("button", {name:"Info"}));
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  expect(await screen.findByText("transfer", {selector:".vx-tool-summary strong"})).toBeDefined();
  expect(screen.queryByRole("button", {name:"Show details for transfer"})).toBeNull();
  fireEvent.change((await filters()).getByLabelText("Tool detail"), {target:{value:"With details"}});
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  fireEvent.click(await screen.findByRole("button", {name:"Show details for transfer"}));
  expect(screen.getByText(/"destination": "Billing"/)).toBeDefined();
});

test("an unassigned evaluation belongs to the executed tool even when an event has its timestamp", async () => {
  const {container} = render(<GuardrailCallDetails scenario="repair-and-transfer" theme="light" />);
  fireEvent.click((await filters()).getByRole("button", {name:"All"}));
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  const transferCard = await screen.findByRole("region", {name:"Before outgoing transfer · Routing agent"});
  expect(transferCard.closest(".vx-timeline-tool")?.textContent).toContain("transfer");
  expect(container.querySelectorAll("#evaluation-check-transfer")).toHaveLength(1);
});

test("hiding messages leaves just the proposed tools with one shared evaluation", async () => {
  render(<GuardrailCallDetails scenario="mixed-proposal" theme="light" />);
  const modal = await filters();
  fireEvent.click(modal.getByLabelText("Messages"));
  fireEvent.click(screen.getByRole("button", {name:"Close dialog"}));
  expect(screen.queryByText("I can look up the other account for you.")).toBeNull();
  expect(await screen.findByText("lookup_account")).toBeDefined();
  expect(screen.getAllByText("Is billing the correct destination?")).toHaveLength(1);
  fireEvent.click((await filters()).getByLabelText("Tools", {selector:"input"}));
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

test("preset matching uses the enabled event settings", async () => {
  render(<GuardrailCallDetails scenario="blocked-input" theme="light" />);
  const modal = await filters();
  fireEvent.click(modal.getByRole("button", {name:"All"}));
  fireEvent.click(modal.getByLabelText("Logs"));
  fireEvent.click(modal.getByLabelText("Events", {selector:"input", exact: true}));
  fireEvent.change(modal.getByLabelText("Tool detail"), {target:{value:"Only calls"}});
  fireEvent.change(modal.getByLabelText("Guardrails"), {target:{value:"None"}});
  expect(modal.getByRole("button", {name:"Info"})).toHaveAttribute("aria-pressed", "true");
});
