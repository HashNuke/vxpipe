import type { Meta, StoryObj } from "@storybook/react-vite";
import { accessComponentsMeta } from "./accessComponentsMeta";

const meta = { ...accessComponentsMeta, title: "Vxpipe/Console/Roles/components/Permissions" } satisfies Meta<typeof accessComponentsMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const PermissionSelection: Story = {
  args: { component: "permissions" },
};
export const MixedPermissionScopes: Story = {
  args: { component: "permissions", variant: "mixed-scopes" },
};
export const EmptyPermissions: Story = {
  args: { component: "permissions", variant: "empty" },
};
