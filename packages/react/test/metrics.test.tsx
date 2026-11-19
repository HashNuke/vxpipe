import { fireEvent, render, screen, within } from "@testing-library/react";
import { expect, test } from "vitest";
import type { Metric } from "@vxpipe/core";
import { Metrics } from "../src/Metrics.js";
import { createFixtureController } from "../stories/fixtureClient.js";

function metric(value: number | null, unit = "milliseconds"): Metric {
  return { label: "TTFT", value, unit, source: "Turn measurement", description: "Model dispatch to text",
    scope: { kind: "participant-capability", participantId: "assistant", capability: "LLM" } };
}

function snapshot(metrics: Metric[]) {
  return { ...createFixtureController("conversation").getSnapshot(), metrics };
}

test("repeated metrics default to a median, average and total summary with expandable observations", () => {
  render(<Metrics snapshot={snapshot([metric(100), metric(300), metric(800)])} theme="dark" />);
  const summary = screen.getByRole("group", { name: "TTFT summary for LLM, Assistant" });
  expect(summary).toHaveTextContent("Median300 ms");
  expect(summary).toHaveTextContent("Avg400 ms");
  expect(summary).toHaveTextContent("Total1,200 ms");
  expect(screen.queryByRole("button", { name: "TTFT for LLM, Assistant: 100 ms" })).not.toBeInTheDocument();
  const toggle = screen.getByRole("button", { name: "Expand metrics for LLM, Assistant" });
  expect(toggle).toHaveAttribute("aria-expanded", "false");
  fireEvent.click(toggle);
  expect(toggle).toHaveAttribute("aria-expanded", "true");
  expect(screen.getByRole("button", { name: "TTFT for LLM, Assistant: 100 ms" })).toBeVisible();
  expect(screen.queryByRole("group", { name: "TTFT summary for LLM, Assistant" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Collapse all" }));
  expect(screen.getByRole("group", { name: "TTFT summary for LLM, Assistant" })).toBeVisible();
});

test("summary excludes unavailable values and keeps incompatible units separate", () => {
  render(<Metrics snapshot={snapshot([metric(100), metric(null), metric(300, "ms"), metric(2, "s")])} theme="light" />);
  const summary = screen.getByRole("group", { name: "TTFT summary for LLM, Assistant" });
  expect(summary).toHaveTextContent("Median200 ms");
  expect(summary).toHaveTextContent("Total400 ms");
  expect(summary).toHaveTextContent("2 of 3 values");
  expect(summary).toHaveTextContent("2 s");
  expect(summary).not.toHaveTextContent("402");
});

test("cells abbreviate units in both summary and expanded views without changing observations", () => {
  const metrics = [metric(10, "characters"), metric(20, "characters"),
    { ...metric(1, "requests"), label: "Requests" }, { ...metric(2, "requests"), label: "Requests" }];
  render(<Metrics snapshot={snapshot(metrics)} theme="dark" />);
  expect(screen.getByRole("group", { name: "TTFT summary for LLM, Assistant" })).toHaveTextContent("Total30 ch");
  expect(screen.getByRole("group", { name: "Requests summary for LLM, Assistant" })).toHaveTextContent("Total3 reqs");
  fireEvent.click(screen.getByRole("button", { name: "Expand all" }));
  const table = screen.getByRole("table", { name: "Call metrics" });
  expect(within(table).getByRole("button", { name: "TTFT for LLM, Assistant: 10 ch" })).toBeVisible();
  expect(within(table).getByRole("button", { name: "Requests for LLM, Assistant: 1 reqs" })).toBeVisible();
  expect(metrics[0]?.unit).toBe("characters");
});

test("all-unavailable series stays unavailable instead of reporting zero", () => {
  render(<Metrics snapshot={snapshot([metric(null), metric(null)])} theme="dark" />);
  expect(screen.getByRole("button", { name: "TTFT for LLM, Assistant: Unavailable" })).toBeVisible();
  expect(screen.queryByText("Total")).not.toBeInTheDocument();
});

test("STT stays one summarized row per participant when all other metrics expand", () => {
  const stt = (participantId: string, value: number): Metric => ({ ...metric(value), label: "Final transcript latency",
    scope: { kind: "participant-capability", participantId, capability: "STT" } });
  const data = snapshot([stt("caller", 100), stt("caller", 300),
    stt("second-caller", 200), stt("second-caller", 400), metric(100), metric(200)]);
  data.participants = [...data.participants, { ...data.participants[0]!, id: "second-caller", name: "Second participant", role: "human" }];
  render(<Metrics snapshot={data} theme="dark" />);
  fireEvent.click(screen.getByRole("button", { name: "Expand all" }));
  expect(screen.getByRole("group", { name: "Final transcript latency summary for STT, Caller" })).toHaveTextContent("Avg200 ms");
  expect(screen.getByRole("group", { name: "Final transcript latency summary for STT, Second participant" })).toHaveTextContent("Avg300 ms");
  expect(screen.getAllByRole("rowheader", { name: /^STT,/ })).toHaveLength(2);
  expect(screen.queryByRole("button", { name: /(?:Expand|Collapse) metrics for STT/ })).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "TTFT for LLM, Assistant: 100 ms" })).toBeVisible();
});
