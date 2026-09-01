import type { Meta, StoryObj } from "@storybook/react-vite";

import { SampleCard } from "./sample-card";

const meta = {
  title: "CallRooms/SampleCard",
  component: SampleCard,
  parameters: { layout: "centered" },
  tags: ["autodocs"],
} satisfies Meta<typeof SampleCard>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Planned: Story = {
  args: {
    sample: {
      description:
        "Send microphone audio to a room and subscribe to the agent output track.",
      id: "websocket-voice-room",
      status: "planned",
      title: "WebSocket voice room",
    },
  },
};

export const Available: Story = {
  args: {
    sample: {
      ...Planned.args?.sample,
      status: "available",
    },
  },
};
