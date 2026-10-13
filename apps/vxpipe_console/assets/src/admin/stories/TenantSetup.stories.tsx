import type { Meta, StoryObj } from "@storybook/react-vite";
import { setupMeta } from "./setupMeta";

const meta = { ...setupMeta, title: "Vxpipe/Console/Tenants/Setup overview" } satisfies Meta<typeof setupMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const DemoNudge: Story = { args: { scenario: "demo-nudge" } };
export const MultipleTenants: Story = {
  args: { scenario: "multiple-tenants" },
};
