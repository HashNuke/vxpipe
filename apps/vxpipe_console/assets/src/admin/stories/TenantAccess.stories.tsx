import type { Meta, StoryObj } from "@storybook/react-vite";
import { accessComponentsMeta } from "./accessComponentsMeta";

const meta = { ...accessComponentsMeta, title: "Vxpipe/Console/Users/components/Tenant access" } satisfies Meta<typeof accessComponentsMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const AssignedTenants: Story = { args: { component: "tenant-access" } };
export const NoTenants: Story = {
  args: { component: "tenant-access", variant: "empty" },
};
export const AllTenants: Story = {
  args: { component: "tenant-access", variant: "all-tenants" },
};
export const MixedTenantGrants: Story = {
  args: { component: "tenant-access", variant: "mixed" },
};
export const ReadOnlyTenantAccess: Story = {
  args: { component: "tenant-access", variant: "read-only" },
};
export const LightTenantAccess: Story = {
  args: { component: "tenant-access", theme: "light" },
};
