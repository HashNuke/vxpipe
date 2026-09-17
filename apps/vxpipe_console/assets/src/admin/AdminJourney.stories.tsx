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
          "Start here to review the linked admin experience. The current implementation connects Tenants → Tenant definitions → Definition calls with working breadcrumbs and browser history. The next checkpoint attaches call details to this same story.",
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
