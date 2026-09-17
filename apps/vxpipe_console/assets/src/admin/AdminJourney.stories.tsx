import type { Meta, StoryObj } from "@storybook/react-vite";

import { AdminJourneyStory } from "./AdminJourneyStory";

const meta = {
  title: "Admin/Full journey",
  component: AdminJourneyStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Start here to review the linked admin experience. Follow Tenants → Tenant definitions → Definition calls → Call details, then use breadcrumbs or browser history to move back through the same pages.",
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
