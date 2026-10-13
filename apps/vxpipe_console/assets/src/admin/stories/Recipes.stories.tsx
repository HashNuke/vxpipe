import type { Meta, StoryObj } from "@storybook/react-vite";
import { setupMeta } from "./setupMeta";

const meta = { ...setupMeta, title: "Vxpipe/Console/Call Specs/Sample call specs" } satisfies Meta<typeof setupMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const BlockedSamples: Story = { args: { scenario: "blocked-samples" } };
export const Samples: Story = { args: { scenario: "samples" } };
export const LoadingSamples: Story = { args: { scenario: "loading-samples" } };
export const SampleError: Story = { args: { scenario: "sample-error" } };
export const Complete: Story = { args: { scenario: "complete" } };
export const SamplesLight: Story = {
  args: { scenario: "samples", theme: "light" },
};
