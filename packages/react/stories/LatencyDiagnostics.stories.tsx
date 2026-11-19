import { useMemo } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { LatencyDiagnostics } from "../src/LatencyDiagnostics.js";
import { createLatencyFixture } from "./latencyFixtures.js";
import "../src/styles.css";

const meta = {
  title: "Vxpipe/Console/Calls/Latency diagnostics",
  component: LatencyDiagnostics,
  args: { loader: createLatencyFixture(), live: false, participants: [{ id: "caller", name: "Caller" }] },
  decorators: [Story => <div className="vx-console" data-vx-theme="dark" style={{ minHeight: "100vh", height: "auto", maxHeight: "none", overflow: "visible", display: "block" }}><Story /></div>],
} satisfies Meta<typeof LatencyDiagnostics>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Collected: Story = {};
export const NotCollected: Story = { args: { loader: createLatencyFixture("empty") } };
export const Unavailable: Story = { args: { loader: createLatencyFixture("unavailable") } };
export const Loading: Story = { args: { loader: createLatencyFixture("loading") } };

export const Denied: Story = { args: { loader: createLatencyFixture("denied") } };
export const Pending: Story = { args: { loader: createLatencyFixture("pending"), live: true } };
export const Unsupported: Story = { args: { loader: createLatencyFixture("unsupported") } };
export const ZeroValidSamples: Story = { args: { loader: createLatencyFixture("zero-valid") } };
export const LargeReport: Story = { args: { loader: createLatencyFixture("large") } };

export const LateEvidence: Story = { render: function Render(args) {
  const loader = useMemo(() => createLatencyFixture("late"), []);
  return <LatencyDiagnostics {...args} loader={loader} />;
} };
export const RetryAfterOutage: Story = { render: function Render(args) {
  const loader = useMemo(() => createLatencyFixture("retry"), []);
  return <LatencyDiagnostics {...args} loader={loader} />;
} };

export const ParticipantSegments: Story = { args: { loader: createLatencyFixture("participants"),
  participants: [{ id: "caller", name: "Caller" }, { id: "second-caller", name: "Second participant" }] } };
