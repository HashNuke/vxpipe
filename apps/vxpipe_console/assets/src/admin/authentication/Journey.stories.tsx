import type { Meta, StoryObj } from "@storybook/react-vite";
import { AuthenticationJourney } from "./AuthenticationJourney";
const meta = {
  title: "Vxpipe/Console/Authentication/Full journey",
  component: AuthenticationJourney,
  args: {
    actor: "superadmin",
    theme: "dark",
    initialPath: "/admin/users",
    followLocation: true,
    saveBehavior: "success",
  },
  argTypes: {
    actor: {
      control: "select",
      options: ["superadmin", "admin", "member", "reader"],
    },
    theme: { control: "select", options: ["dark", "light"] },
    saveBehavior: {
      control: "select",
      options: ["success", "failure", "pending"],
    },
  },
  parameters: {
    docs: {
      description: {
        component:
          "Start here. Create a role, create a user, assign tenants, filter the directory, edit access and reset passwords. Try actor=admin to view protected accounts. Sign out and sign in with an example.test fixture email and any nonempty password. Setup starts a fresh mock installation. Changes are in memory and reset on reload; no credentials are stored or sent. Hash URLs model the planned routes without taking over Storybook. Backend implementation waits for UI approval.",
      },
    },
  },
  render: (args) => (
    <AuthenticationJourney
      key={`${args.actor}-${args.initialPath}-${args.theme}-${args.saveBehavior}`}
      {...args}
    />
  ),
} satisfies Meta<typeof AuthenticationJourney>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Superadmin: Story = {};
export const Admin: Story = { args: { actor: "admin" } };
export const FirstInstallation: Story = {
  args: { initialPath: "/auth/setup", followLocation: false },
};
export const DirectoryReader: Story = { args: { actor: "reader" } };
export const Light: Story = { args: { theme: "light" } };
