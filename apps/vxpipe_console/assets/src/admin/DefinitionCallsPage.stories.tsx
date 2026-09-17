import type { Meta, StoryObj } from "@storybook/react-vite";

import { DefinitionCallsStory } from "./DefinitionCallsStory";

const meta = {
  title: "Admin/Definition calls",
  component: DefinitionCallsStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Calls for one definition across all immutable revisions, with lifecycle and archive state kept separate. Use Admin / Full journey to review the linked flow.",
      },
    },
  },
  args: { scenario: "populated", theme: "dark" },
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
    <DefinitionCallsStory key={`${args.theme}-${args.scenario}`} {...args} />
  ),
} satisfies Meta<typeof DefinitionCallsStory>;

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
