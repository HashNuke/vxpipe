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
