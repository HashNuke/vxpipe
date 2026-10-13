import type { Meta, StoryObj } from "@storybook/react-vite";
import { accessMeta } from "./accessMeta";

const meta = { ...accessMeta, title: "Vxpipe/Console/Authentication/Sign in", args: { ...accessMeta.args, initialPath: "/auth/login" } } satisfies Meta<typeof accessMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Setup: Story = { args: { initialPath: "/auth/setup" } };
export const Login: Story = { args: { initialPath: "/auth/login" } };
export const Recovery: Story = { args: { initialPath: "/auth/recover" } };
