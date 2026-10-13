import type { Meta, StoryObj } from "@storybook/react-vite";

import { TenantDirectoryStory } from "./stories/ResourceStories";

const meta = {
  title: "Vxpipe/Console/Tenants/Directory",
  component: TenantDirectoryStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "The installation-wide tenant directory. Stories use deterministic view models and injected navigation; no Phoenix route or database is required.",
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
  render: (args) => <TenantDirectoryStory key={`${args.theme}-${args.scenario}`} {...args} />,
} satisfies Meta<typeof TenantDirectoryStory>;

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
