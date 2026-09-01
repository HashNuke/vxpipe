import type { Meta, StoryObj } from "@storybook/react-vite";

import { SamplesPage } from "./samples-page";

const sample = {
  description:
    "Send microphone audio to a room and subscribe to the agent output track.",
  id: "websocket-voice-room",
  status: "planned" as const,
  title: "WebSocket voice room",
};

const meta = {
  title: "Pages/Samples",
  component: SamplesPage,
  parameters: { layout: "fullscreen" },
  tags: ["autodocs"],
} satisfies Meta<typeof SamplesPage>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Ready: Story = {
  args: { backendState: "connected", samples: [sample] },
};

export const Loading: Story = {
  args: { backendState: "loading", samples: [] },
};

export const Empty: Story = {
  args: { backendState: "connected", samples: [] },
};

export const Disconnected: Story = {
  args: { backendState: "disconnected", samples: [sample] },
};
