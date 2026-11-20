import type { Meta, StoryObj } from "@storybook/react-vite";

import { CallDetailsStory } from "./CallDetailsStory";

const meta = {
  title: "Vxpipe/Console/Calls/History",
  component: CallDetailsStory,
  parameters: { layout: "fullscreen" },
  args: { scenario: "ongoing", theme: "dark" },
  argTypes: {
    scenario: {
      control: "select",
      options: [
        "ongoing",
        "ended",
        "partial-archive",
        "long-content",
        "metrics",
        "loading",
        "unavailable",
        "malformed-response",
      ],
    },
    theme: { control: "select", options: ["dark", "light"] },
  },
  render: (args) => <CallDetailsStory key={`${args.scenario}-${args.theme}`} {...args} />,
} satisfies Meta<typeof CallDetailsStory>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Ongoing: Story = {};
export const Ended: Story = { args: { scenario: "ended" } };
export const PartialArchive: Story = { args: { scenario: "partial-archive" } };
export const LongContent: Story = { args: { scenario: "long-content" } };
export const Metrics: Story = {
  args: { scenario: "metrics", initialTab: "metrics", latency: "combined" },
  parameters: { docs: { description: { story: "Twelve synthetic turns and two participant STT sessions. STT stays summarized per participant; LLM, TTS and VAD rows can expand. Each human's VAD row (local Silero) carries end-of-turn detection (EOT) and barge-in stop delay as median, p95 and valid counts; per-turn evidence opens from an expanded measurement." } } },
};
export const Loading: Story = { args: { scenario: "loading" } };
export const Unavailable: Story = { args: { scenario: "unavailable" } };
export const MalformedResponse: Story = { args: { scenario: "malformed-response" } };
export const Narrow: Story = {
  globals: { viewport: { value: "390px-844px", isRotated: false } },
};

export const Latency: Story = {
  args: { scenario: "metrics", initialTab: "metrics", latency: true },
  parameters: { docs: { description: { story: "Synthetic optional latency diagnostics as a VAD row. Fetched when the Metrics tab opens; complete and partial turn evidence remain distinct." } } },
};

export const LatencyLoading: Story = { args: { scenario: "metrics", initialTab: "metrics", latency: "loading" } };
export const LatencyRetry: Story = { args: { scenario: "metrics", initialTab: "metrics", latency: "retry" } };
export const LatencyLarge: Story = { args: { scenario: "metrics", initialTab: "metrics", latency: "large" } };

export const ParticipantSegments: Story = { args: { scenario: "metrics", initialTab: "metrics", latency: "participants" },
  parameters: { docs: { description: { story: "Synthetic participant-owned VAD evidence: two human STT observations, multiple segments per turn, agent-transfer continuity, and explicit missing/omitted evidence." } } } };

export const BargeInLatency: Story = { args: { scenario: "metrics", initialTab: "metrics", latency: "barge-in" },
  parameters: { docs: { description: { story: "Synthetic barge-in stop measurements in the VAD row; available, ambiguous-onset and missing-stop turns remain distinct when expanded." } } } };
