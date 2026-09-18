import type { Meta, StoryObj } from "@storybook/react-vite";

import { TenantCallSpecsStory } from "./TenantCallSpecsStory";

const meta = {
  title: "vxpipe_console/Tenant call specs",
  component: TenantCallSpecsStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Call specs for one tenant, including publication state, latest saved version, all-version call totals, and filtered Calls links. The complete linked flow is available under Admin / Full journey.",
      },
    },
  },
  args: {
    scenario: "populated",
    theme: "dark",
  },
  argTypes: {
    scenario: {
      control: "select",
      options: [
        "populated",
        "loading",
        "empty",
        "unavailable",
        "long-content",
        "paginated",
      ],
    },
    theme: { control: "select", options: ["dark", "light"] },
  },
  render: (args) => (
    <TenantCallSpecsStory
      key={`${args.theme}-${args.scenario}`}
      {...args}
    />
  ),
} satisfies Meta<typeof TenantCallSpecsStory>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Populated: Story = {};
export const Loading: Story = { args: { scenario: "loading" } };
export const Empty: Story = { args: { scenario: "empty" } };
export const Unavailable: Story = { args: { scenario: "unavailable" } };
export const LongContent: Story = { args: { scenario: "long-content" } };
export const Paginated: Story = { args: { scenario: "paginated" } };
export const Light: Story = { args: { theme: "light" } };
export const Narrow: Story = {
  globals: {
    viewport: { value: "390px-844px", isRotated: false },
  },
};
