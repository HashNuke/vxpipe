import type { Meta, StoryObj } from "@storybook/react-vite";

import { AdminJourneyStory } from "./AdminJourneyStory";

const meta = {
  title: "vxpipe_console/Full journey",
  component: AdminJourneyStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Start here to review the linked admin experience. Follow Tenants → Call definitions → filtered Calls, then open a call in its own inspection tab. The original directory keeps its filters and position. Use the tenant navigation to review all Calls or Services.",
      },
    },
  },
  args: { theme: "dark" },
  argTypes: {
    theme: { control: "select", options: ["dark", "light"] },
  },
  render: (args) => <AdminJourneyStory key={args.theme} {...args} />,
} satisfies Meta<typeof AdminJourneyStory>;

export default meta;
type Story = StoryObj<typeof meta>;

export const ReviewFlow: Story = {};
export const Narrow: Story = {
  globals: {
    viewport: { value: "390px-844px", isRotated: false },
  },
};
