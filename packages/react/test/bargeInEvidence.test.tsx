import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { BargeInEvidence, BargeInSummary } from "../src/BargeInEvidence.js";

const bargeInEvidence = { version: 1 as const, omittedCount: 0, reasons: [], entries: [{
  outputId: "old-output", agentParticipantId: "agent", responseSourceParticipantId: "other-human",
  outputConnectionId: "other-browser", responseTurnId: "old-turn", responseCommandId: "old-command",
  playbackStartedUs: 100000, interruptionRequestedUs: 350000, playbackStoppedUs: 380000,
  speechStartedUs: 300000, speechStartConfirmedUs: 450000, speechStartSample: 4800,
  epoch: 0, uncertaintyUs: 32000, durationUs: 80000, boundary: "server_egress" as const, reasons: [],
}] };

test("positive sub-millisecond barge-in uncertainty is not displayed as zero", () => {
  const evidence = { ...bargeInEvidence, entries: [{ ...bargeInEvidence.entries[0]!,
    playbackStartedUs: 10000, speechStartedUs: 20000, interruptionRequestedUs: 30000,
    playbackStoppedUs: 35000, speechStartConfirmedUs: 40000, speechStartSample: 320,
    uncertaintyUs: 100, durationUs: 15000,
  }] };
  render(<BargeInEvidence evidence={evidence} name={id => id} />);
  expect(screen.getByText("20 ms")).toBeVisible();
  expect(screen.getByText("35 ms")).toBeVisible();
  expect(screen.getByText("15 ms")).toBeVisible();
  expect(screen.getByText("Uncertainty <1 ms")).toBeVisible();
  expect(screen.queryByText("Uncertainty 0 ms")).not.toBeInTheDocument();
});

test.each([
  [1, "<1 ms"], [100, "<1 ms"], [999, "<1 ms"], [0, "0 ms"],
  [null, "Unavailable"], [1000, "1 ms"], [15000, "15 ms"],
] as const)("barge-in summary preserves the distinction for %s microseconds", (durationUs, label) => {
  const evidence = { ...bargeInEvidence, entries: [{ ...bargeInEvidence.entries[0]!, durationUs }] };
  render(<BargeInSummary evidence={evidence} />);
  expect(screen.getByText(label)).toBeVisible();
});
