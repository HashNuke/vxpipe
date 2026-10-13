import type { Meta, StoryObj } from "@storybook/react-vite";
import { AuthenticationJourney } from "./AuthenticationJourney";
import { roles, users } from "./fixtures";
const meta = {
  title: "Vxpipe/Console/Authentication/Pages",
  component: AuthenticationJourney,
  args: {
    actor: "superadmin",
    theme: "dark",
    initialPath: "/admin/users",
    followLocation: false,
    state: "ready",
    saveBehavior: "success",
  },
  argTypes: {
    actor: {
      control: "select",
      options: ["superadmin", "admin", "member"],
    },
    theme: { control: "select", options: ["dark", "light"] },
    state: { control: "select", options: ["ready", "loading", "unavailable"] },
    saveBehavior: {
      control: "select",
      options: ["success", "failure", "pending"],
    },
  },
  parameters: {
    docs: {
      description: {
        component:
          "All ten planned routes, composed from the smaller authentication components. Changes live in this story only. Email is an identifier; no emails or backend calls are made. Example accounts accept any nonempty password in this mock. Reset/create forms enforce confirmation and 15–128 characters. Change actor in Controls to review authority.",
      },
    },
  },
  render: (args) => (
    <AuthenticationJourney
      key={`${args.actor}-${args.initialPath}-${args.theme}-${args.state}-${args.saveBehavior}`}
      {...args}
    />
  ),
} satisfies Meta<typeof AuthenticationJourney>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Setup: Story = { args: { initialPath: "/auth/setup" } };
export const Login: Story = { args: { initialPath: "/auth/login" } };
export const Recovery: Story = { args: { initialPath: "/auth/recover" } };
export const Account: Story = { args: { initialPath: "/admin/account" } };
export const Users: Story = {};
export const CreateUser: Story = { args: { initialPath: "/admin/users/new" } };
export const UserDetails: Story = {
  args: { initialPath: `/admin/users/${users[4].id}` },
};
export const ResetPassword: Story = {
  args: { initialPath: `/admin/users/${users[1].id}/reset-password` },
};
export const Roles: Story = { args: { initialPath: "/admin/roles" } };
export const CreateRole: Story = { args: { initialPath: "/admin/roles/new" } };
export const RoleDetails: Story = {
  args: { initialPath: `/admin/roles/${roles[2].id}` },
};
export const AdminViewsSuperadmin: Story = {
  args: { actor: "admin", initialPath: `/admin/users/${users[0].id}` },
};
export const MemberDenied: Story = { args: { actor: "member" } };
export const ProtectedRole: Story = {
  args: { initialPath: `/admin/roles/${roles[0].id}` },
};
export const LastSuperadmin: Story = {
  args: { initialPath: `/admin/users/${users[0].id}` },
};
export const AssignedTenantAccess: Story = {
  args: { initialPath: `/admin/users/${users[5].id}` },
};
export const UnassignedUser: Story = {
  args: { initialPath: `/admin/users/${users[7].id}` },
};
export const DisabledUser: Story = {
  args: { initialPath: `/admin/users/${users[8].id}` },
};
export const EmptyResults: Story = {
  args: { initialPath: "/admin/users?q=no-match" },
};
export const LoadingUsers: Story = { args: { state: "loading" } };
export const UnavailableUsers: Story = { args: { state: "unavailable" } };
export const SaveFailure: Story = {
  args: { initialPath: `/admin/users/${users[4].id}`, saveBehavior: "failure" },
};
export const ResetFailure: Story = {
  args: {
    initialPath: `/admin/users/${users[4].id}/reset-password`,
    saveBehavior: "failure",
  },
};
export const PendingSave: Story = {
  args: { initialPath: "/admin/users/new", saveBehavior: "pending" },
};
export const LightUsers: Story = { args: { theme: "light" } };
