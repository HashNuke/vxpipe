import type { Meta, StoryObj } from "@storybook/react-vite";

import { BackendStatus } from "./backend-status";

const meta = {
  title: "UI/BackendStatus",
  component: BackendStatus,
  parameters: { layout: "centered" },
  tags: ["autodocs"],
} satisfies Meta<typeof BackendStatus>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Connected: Story = {
  args: { state: "connected" },
};

export const Loading: Story = {
  args: { state: "loading" },
};

export const Disconnected: Story = {
  args: { state: "disconnected" },
};
