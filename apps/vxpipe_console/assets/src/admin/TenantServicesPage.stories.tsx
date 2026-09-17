import type { Meta, StoryObj } from "@storybook/react-vite";

import { TenantServicesStory } from "./TenantServicesStory";

const meta = {
  title: "Admin/Services",
  component: TenantServicesStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Tenant service inventory and create-only credential setup. Stored secrets are never returned or rendered.",
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
        "partial",
        "unavailable",
        "long-content",
        "validation-error",
        "submission-pending",
        "save-failure",
        "duplicate-conflict",
        "save-success",
      ],
    },
    theme: { control: "select", options: ["dark", "light"] },
  },
  render: (args) => (
    <TenantServicesStory key={`${args.theme}-${args.scenario}`} {...args} />
  ),
} satisfies Meta<typeof TenantServicesStory>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Populated: Story = {};
export const Loading: Story = { args: { scenario: "loading" } };
export const Empty: Story = { args: { scenario: "empty" } };
export const PartialInventory: Story = { args: { scenario: "partial" } };
export const Unavailable: Story = { args: { scenario: "unavailable" } };
export const LongContent: Story = { args: { scenario: "long-content" } };
export const ValidationError: Story = { args: { scenario: "validation-error" } };
export const SubmissionPending: Story = { args: { scenario: "submission-pending" } };
export const SaveFailure: Story = { args: { scenario: "save-failure" } };
export const DuplicateConflict: Story = { args: { scenario: "duplicate-conflict" } };
export const SaveSuccess: Story = { args: { scenario: "save-success" } };
export const Light: Story = { args: { theme: "light" } };
export const Narrow: Story = {
  globals: { viewport: { value: "390px-844px", isRotated: false } },
};
