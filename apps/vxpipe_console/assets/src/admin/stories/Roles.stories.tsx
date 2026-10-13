import type { Meta, StoryObj } from "@storybook/react-vite";
import { accessMeta } from "./accessMeta";
import { roles } from "../authentication/fixtures";

const meta = { ...accessMeta, title: "Vxpipe/Console/Roles/Roles", args: { ...accessMeta.args, initialPath: "/roles" } } satisfies Meta<typeof accessMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Roles: Story = { args: { initialPath: "/roles" } };
export const CreateRole: Story = { args: { initialPath: "/roles/new" } };
export const RoleDetails: Story = {
  args: { initialPath: `/roles/${roles[2].id}` },
};
export const ProtectedRole: Story = {
  args: { initialPath: `/roles/${roles[0].id}` },
};
