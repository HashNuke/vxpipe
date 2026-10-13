import type { Meta } from "@storybook/react-vite";
import { AuthenticationStory } from "./AuthenticationStory";
export const accessMeta = {
  component: AuthenticationStory,
  args: {
    actor: "superadmin",
    theme: "dark",
    initialPath: "/users",
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
          "Authentication and account administration with local fixtures. Changes live in this story only. Email is an identifier; no emails or backend calls are made. Example accounts accept any nonempty password in this mock. Reset/create forms enforce confirmation and 15–128 characters.",
      },
    },
  },
  render: (args) => (
    <AuthenticationStory
      key={`${args.actor}-${args.initialPath}-${args.theme}-${args.state}-${args.saveBehavior}`}
      {...args}
    />
  ),
} satisfies Meta<typeof AuthenticationStory>;
