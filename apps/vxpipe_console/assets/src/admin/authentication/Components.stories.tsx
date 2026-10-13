import type { Meta, StoryObj } from "@storybook/react-vite";
import { ComponentExamples } from "./ComponentExamples";
const meta = {
  title: "Vxpipe/Console/Authentication/Components",
  component: ComponentExamples,
  args: { component: "passwords", theme: "dark", variant: "default" },
  argTypes: {
    component: {
      control: "select",
      options: [
        "passwords",
        "badges",
        "role-select",
        "tenant-access",
        "permissions",
      ],
    },
    theme: { control: "select", options: ["dark", "light"] },
    variant: {
      control: "select",
      options: [
        "default",
        "empty",
        "all-tenants",
        "mixed",
        "mixed-scopes",
        "read-only",
        "admin",
      ],
    },
  },
  parameters: {
    docs: {
      description: {
        component:
          "Small interactive building blocks shared by the authentication pages. Local fixtures only; no backend requests.",
      },
    },
  },
  render: (args) => (
    <ComponentExamples
      key={`${args.component}-${args.variant}-${args.theme}`}
      {...args}
    />
  ),
} satisfies Meta<typeof ComponentExamples>;
export default meta;
type Story = StoryObj<typeof meta>;
export const PasswordAndConfirmation: Story = {};
export const RoleBadges: Story = { args: { component: "badges" } };
export const RoleSelection: Story = { args: { component: "role-select" } };
export const AdminRoleSelection: Story = {
  args: { component: "role-select", variant: "admin" },
};
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
export const PermissionSelection: Story = {
  args: { component: "permissions" },
};
export const MixedPermissionScopes: Story = {
  args: { component: "permissions", variant: "mixed-scopes" },
};
export const EmptyPermissions: Story = {
  args: { component: "permissions", variant: "empty" },
};
export const LightTenantAccess: Story = {
  args: { component: "tenant-access", theme: "light" },
};
