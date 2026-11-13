import type { Meta, StoryObj } from "@storybook/react-vite";
import { AdminShell } from "../AdminShell";
import { CopyButton } from "../CopyButton";

const meta = {
  title: "Vxpipe/Console/shared/Copy button",
  component: CopyButton,
  args: { value: "https://example.com/webhook", "aria-label": "Copy webhook URL" },
  parameters: { docs: { description: { component:
    "Use CopyButton for clipboard actions throughout the console. Pass value, an optional visible label, and an accessible name for context. Success shows a checkmark and Copied for two seconds without changing width; failures offer manual recovery beside the button. No separate success toast is needed.",
  } } },
  decorators: [Story => <AdminShell theme="dark" showHeader={false}><div className="p-6"><Story /></div></AdminShell>],
} satisfies Meta<typeof CopyButton>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {};
export const ApiKey: Story = { args: { value: "example-key", label: "Copy API key", "aria-label": "Copy API key" } };
export const Json: Story = { args: { value: '{"name":"Receptionist"}', label: "Copy JSON", "aria-label": "Copy JSON" } };
export const Disabled: Story = { args: { disabled: true } };
export const Light: Story = {
  render: args => <AdminShell theme="light" showHeader={false}><div className="p-6"><CopyButton {...args} /></div></AdminShell>,
};
