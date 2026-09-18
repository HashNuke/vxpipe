import type { Meta, StoryObj } from "@storybook/react-vite";

import { CallSpecCallsStory } from "./CallSpecCallsStory";

const meta = {
  title: "vxpipe_console/Calls",
  component: CallSpecCallsStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "All calls for one tenant, with an optional URL-backed call spec filter. Use Admin / Full journey to review the linked flow.",
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
        "filtered",
        "no-filter-matches",
        "unknown-filter",
        "unavailable",
        "truncated-options",
        "long-content",
        "paginated",
      ],
    },
    theme: { control: "select", options: ["dark", "light"] },
  },
  render: (args) => (
    <CallSpecCallsStory key={`${args.theme}-${args.scenario}`} {...args} />
  ),
} satisfies Meta<typeof CallSpecCallsStory>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Populated: Story = {};
export const Loading: Story = { args: { scenario: "loading" } };
export const Empty: Story = { args: { scenario: "empty" } };
export const Filtered: Story = { args: { scenario: "filtered" } };
export const NoFilterMatches: Story = { args: { scenario: "no-filter-matches" } };
export const UnknownFilter: Story = { args: { scenario: "unknown-filter" } };
export const Unavailable: Story = { args: { scenario: "unavailable" } };
export const TruncatedOptions: Story = { args: { scenario: "truncated-options" } };
export const LongContent: Story = { args: { scenario: "long-content" } };
export const Paginated: Story = { args: { scenario: "paginated" } };
export const Light: Story = { args: { theme: "light" } };
export const Narrow: Story = {
  globals: {
    viewport: { value: "390px-844px", isRotated: false },
  },
};
