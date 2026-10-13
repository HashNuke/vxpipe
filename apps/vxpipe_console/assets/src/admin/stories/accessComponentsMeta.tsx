import type { Meta } from "@storybook/react-vite";
import { ComponentExamples } from "../authentication/ComponentExamples";
export const accessComponentsMeta = {
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
