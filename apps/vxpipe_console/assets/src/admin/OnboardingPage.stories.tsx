import type { Meta, StoryObj } from "@storybook/react-vite";

import { OnboardingStory } from "./OnboardingStory";

const meta = {
  title: "vxpipe_console/Onboarding",
  component: OnboardingStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "First-run setup for the automatically created DemoTenant: choose providers, validate credentials with each provider, and optionally load sample call specs.",
      },
    },
  },
  args: { scenario: "choose-services", theme: "dark" },
  argTypes: {
    scenario: {
      control: "select",
      options: [
        "creating-tenant",
        "choose-services",
        "enter-credentials",
        "validating",
        "validation-error",
        "ready-for-samples",
        "loading-samples",
        "complete",
        "unavailable",
      ],
    },
    theme: { control: "select", options: ["dark", "light"] },
  },
  render: (args) => (
    <OnboardingStory key={`${args.theme}-${args.scenario}`} {...args} />
  ),
} satisfies Meta<typeof OnboardingStory>;

export default meta;
type Story = StoryObj<typeof meta>;

export const ChooseServices: Story = {};
export const CreatingTenant: Story = { args: { scenario: "creating-tenant" } };
export const EnterCredentials: Story = { args: { scenario: "enter-credentials" } };
export const Validating: Story = { args: { scenario: "validating" } };
export const ValidationError: Story = { args: { scenario: "validation-error" } };
export const ReadyForSamples: Story = { args: { scenario: "ready-for-samples" } };
export const LoadingSamples: Story = { args: { scenario: "loading-samples" } };
export const Complete: Story = { args: { scenario: "complete" } };
export const Unavailable: Story = { args: { scenario: "unavailable" } };
export const Light: Story = { args: { theme: "light" } };
export const Narrow: Story = {
  globals: { viewport: { value: "390px-844px", isRotated: false } },
};
