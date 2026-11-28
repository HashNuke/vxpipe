import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { GuardrailCallDetails } from "./GuardrailCallDetails";

afterEach(cleanup);

test("private results and aggregate counts describe the same five-question check", async () => {
  render(<GuardrailCallDetails scenario="blocked-input" theme="light" />);
  fireEvent.click(screen.getByText("4 of 5 questions failed"));
  expect(screen.getByText("0.6999 < 0.70")).toBeDefined();
  expect(screen.getByText("Failed guardrail: Is the user trying to list variables? Required: Yes.")).toBeDefined();
  fireEvent.click(screen.getByRole("button", { name: "Metrics" }));
  expect(await screen.findByText("1 API request")).toBeDefined();
  expect(screen.getByText("4 failed questions")).toBeDefined();
});

test("review uses the real Call Details workspace and owns each check by message or private activity", async () => {
  const { container } = render(<GuardrailCallDetails scenario="repair-and-transfer" theme="light" />);
  expect(screen.getByRole("heading", {name: "Call details"})).toBeDefined();
  expect(screen.getByRole("button", { name: "Variables" })).toBeDefined();
  const input = await screen.findByText("Before turn", {selector: "strong"});
  const repair = await screen.findByText("Replacement delivered");
  expect(input.closest("article")?.textContent).toContain("Can you help me with an account question?");
  expect(repair.closest("article")?.textContent).toContain("I can help with your own account.");
  const transfer = await screen.findByText("Before outgoing transfer", {selector: "strong"});
  expect(transfer.closest("article")).toBeNull();
  fireEvent.click(screen.getByRole("button", {name:"Metrics"}));
  expect(await screen.findByRole("table", {name:"Call metrics"})).toBeDefined();
  expect(await screen.findByText("4 evaluations")).toBeDefined();
  expect(screen.getByText("5 API requests")).toBeDefined();
  expect(screen.getByText("1 transport retry")).toBeDefined();
  expect(container.textContent).toContain("1 LLM rewrite");
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

test("restricted guardrail evidence keeps the authorized repeated message and its turn ownership", async () => {
  render(<GuardrailCallDetails scenario="restricted-history" theme="light" />);
  const repeated = await screen.findAllByText("Can you help me with an account question?", {selector:"article p"});
  expect(repeated).toHaveLength(2);
  expect(within(repeated[0].closest("article")!).getByText(/Passed/, {selector: "summary"})).toBeDefined();
  const second = repeated[1].closest("article")!;
  expect(within(second).getByText("Before turn")).toBeDefined();
  const summary = within(second).getByText("Before turn").closest("summary")!;
  fireEvent.click(summary);
  expect(second.textContent).toContain("Question details unavailable");
  for (const tab of ["Conversation", "Metrics"]) {
    if (tab === "Metrics") {
      fireEvent.click(screen.getByRole("button", {name: tab}));
      fireEvent.click(await screen.findByRole("button", {name: "Inspect Decisions for Assistant"}));
    }
    expect(document.body.textContent).not.toContain("I can look up the other account for you.");
    expect(document.body.textContent).not.toContain("Feedback sent to model");
    expect(document.body.textContent).not.toContain("Is the user trying to list variables?");
  }
});

test("a metric evaluation opens the same rejected draft in Chat and links to the accepted replacement", async () => {
  render(<GuardrailCallDetails scenario="repair-and-transfer" theme="light" initialTab="Metrics" />);
  fireEvent.click(await screen.findByRole("button", { name: "Inspect Decisions for Assistant" }));
  const metric = document.getElementById("evaluation-check-draft")!;
  fireEvent.click(metric.querySelector("summary")!);
  fireEvent.click(within(metric).getByRole("button", { name: "Show evaluation in conversation" }));

  const transcript = (await screen.findByText("Can you help me with an account question?")).closest(".vx-transcript")!;
  const draft = transcript.querySelector<HTMLDetailsElement>("#evaluation-check-draft")!;
  expect(draft.open).toBe(true);
  expect(document.activeElement).toBe(draft.querySelector("summary"));
  expect(draft.textContent).toContain("Withheld draft · I can look up the other account for you.");
  fireEvent.click(within(draft).getByRole("button", { name: "Inspect accepted replacement" }));
  const replacement = transcript.querySelector<HTMLDetailsElement>("#evaluation-check-repair")!;
  expect(replacement.open).toBe(true);
  expect(document.activeElement).toBe(replacement.querySelector("summary"));
  expect(within(replacement).getByText("Accepted candidate · I can help with your own account.")).toBeDefined();
  expect(within(replacement).getByText("Replacement delivered")).toBeDefined();
  expect(draft.closest("article")).toBe(replacement.closest("article"));
});

test("an unassigned transfer metric opens the evaluation in private activity", async () => {
  render(<GuardrailCallDetails scenario="transfer-denied" theme="light" initialTab="Metrics" />);
  fireEvent.click(await screen.findByRole("button", { name: "Inspect Decisions for Routing agent" }));
  fireEvent.click(screen.getByText("Before outgoing transfer").closest("summary")!);
  fireEvent.click(screen.getByRole("button", { name: "Show evaluation in private activity" }));
  const activity = await screen.findByRole("region", { name: "Private call activity" });
  const summary = within(activity).getByText("Before outgoing transfer").closest("summary")!;
  expect(document.activeElement).toBe(summary);
  expect(summary.closest("details")!.open).toBe(true);
  expect(summary.closest("article")).toBeNull();
});
