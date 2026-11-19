import type { Meta, StoryObj } from "@storybook/react-vite";

import { CallDetailsStory } from "./CallDetailsStory";

const meta = {
  title: "Vxpipe/Console/Calls/History",
  component: CallDetailsStory,
  parameters: { layout: "fullscreen" },
  args: { scenario: "ongoing", theme: "dark" },
  argTypes: {
    scenario: {
      control: "select",
      options: [
        "ongoing",
        "ended",
        "partial-archive",
        "long-content",
        "metrics",
        "loading",
        "unavailable",
        "malformed-response",
      ],
    },
    theme: { control: "select", options: ["dark", "light"] },
  },
  render: (args) => <CallDetailsStory key={`${args.scenario}-${args.theme}`} {...args} />,
} satisfies Meta<typeof CallDetailsStory>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Ongoing: Story = {};
export const Ended: Story = { args: { scenario: "ended" } };
export const PartialArchive: Story = { args: { scenario: "partial-archive" } };
export const LongContent: Story = { args: { scenario: "long-content" } };
export const Metrics: Story = {
  args: { scenario: "metrics", initialTab: "metrics" },
  parameters: { docs: { description: { story: "Twelve synthetic turns and two participant STT sessions. STT stays summarized per participant; LLM and TTS measurements can expand. Labels stay at the top with expand controls on the right." } } },
};
export const Loading: Story = { args: { scenario: "loading" } };
export const Unavailable: Story = { args: { scenario: "unavailable" } };
export const MalformedResponse: Story = { args: { scenario: "malformed-response" } };
export const Narrow: Story = {
  globals: { viewport: { value: "390px-844px", isRotated: false } },
};
