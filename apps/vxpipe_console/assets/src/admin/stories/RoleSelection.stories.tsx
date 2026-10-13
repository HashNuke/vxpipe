import type { Meta, StoryObj } from "@storybook/react-vite";
import { accessComponentsMeta } from "./accessComponentsMeta";

const meta = { ...accessComponentsMeta, title: "Vxpipe/Console/Users/components/Role selection" } satisfies Meta<typeof accessComponentsMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const RoleSelection: Story = { args: { component: "role-select" } };
export const AdminRoleSelection: Story = {
  args: { component: "role-select", variant: "admin" },
};
