import type { Meta, StoryObj } from "@storybook/react-vite";

import { TenantDefinitionsStory } from "./TenantDefinitionsStory";

const meta = {
  title: "Admin/Tenant definitions",
  component: TenantDefinitionsStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Call definitions for one tenant, including publication state, immutable revision context, and intended admin links. The complete linked flow is available under Admin / Full journey.",
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
    <TenantDefinitionsStory
      key={`${args.theme}-${args.scenario}`}
      {...args}
    />
  ),
} satisfies Meta<typeof TenantDefinitionsStory>;

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
