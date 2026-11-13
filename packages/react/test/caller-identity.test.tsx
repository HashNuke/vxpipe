import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { ParticipantDetails } from "../src/ParticipantDetails.js";

test("shows caller ID, SIP URI and display name as distinct values", () => {
  render(<ParticipantDetails participant={{
    id: "caller", name: "Caller", role: "caller", state: "left", description: null,
    connection: { kind: "phone", phoneNumber: "+15550001001", sipUri: "sip:caller@example.com", callerIdName: "Example caller" },
    capabilities: [], systemPrompt: null, transferPolicies: [], tools: [],
  }} />);
  expect(screen.getByText("Caller ID number")).toBeInTheDocument();
  expect(screen.getByText("+15550001001")).toBeInTheDocument();
  expect(screen.getByText("SIP address")).toBeInTheDocument();
  expect(screen.getByText("sip:caller@example.com")).toBeInTheDocument();
  expect(screen.getByText("Caller ID name")).toBeInTheDocument();
  expect(screen.getByText("Example caller")).toBeInTheDocument();
});

test("shows a SIP-only caller without promoting a numeric display name to caller ID", () => {
  render(<ParticipantDetails participant={{
    id: "caller", name: "Caller", role: "caller", state: "left", description: null,
    connection: { kind: "sip", sipUri: "sips:caller@example.com", callerIdName: "+15550001003" },
    capabilities: [], systemPrompt: null, transferPolicies: [], tools: [],
  }} />);
  expect(screen.getByText("Not provided")).toBeInTheDocument();
  expect(screen.getByText("sips:caller@example.com")).toBeInTheDocument();
  expect(screen.getByText("+15550001003")).toBeInTheDocument();
});
