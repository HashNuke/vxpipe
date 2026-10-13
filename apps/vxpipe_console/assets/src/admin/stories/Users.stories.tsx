import type { Meta, StoryObj } from "@storybook/react-vite";
import { accessMeta } from "./accessMeta";
import { users } from "../authentication/fixtures";

const meta = { ...accessMeta, title: "Vxpipe/Console/Users/Users" } satisfies Meta<typeof accessMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Users: Story = {};
export const CreateUser: Story = { args: { initialPath: "/users/new" } };
export const UserDetails: Story = {
  args: { initialPath: `/users/${users[4].id}` },
};
export const ResetPassword: Story = {
  args: { initialPath: `/users/${users[1].id}/reset-password` },
};
export const AdminViewsSuperadmin: Story = {
  args: { actor: "admin", initialPath: `/users/${users[0].id}` },
};
export const MemberDenied: Story = { args: { actor: "member" } };
export const LastSuperadmin: Story = {
  args: { initialPath: `/users/${users[0].id}` },
};
export const AssignedTenantAccess: Story = {
  args: { initialPath: `/users/${users[5].id}` },
};
export const UnassignedUser: Story = {
  args: { initialPath: `/users/${users[7].id}` },
};
export const DisabledUser: Story = {
  args: { initialPath: `/users/${users[8].id}` },
};
export const EmptyResults: Story = {
  args: { initialPath: "/users?q=no-match" },
};
export const LoadingUsers: Story = { args: { state: "loading" } };
export const UnavailableUsers: Story = { args: { state: "unavailable" } };
export const SaveFailure: Story = {
  args: { initialPath: `/users/${users[4].id}`, saveBehavior: "failure" },
};
export const ResetFailure: Story = {
  args: {
    initialPath: `/users/${users[4].id}/reset-password`,
    saveBehavior: "failure",
  },
};
export const PendingSave: Story = {
  args: { initialPath: "/users/new", saveBehavior: "pending" },
};
export const LightUsers: Story = { args: { theme: "light" } };
