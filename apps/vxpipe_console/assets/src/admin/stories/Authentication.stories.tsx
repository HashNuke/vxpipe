import type { Meta, StoryObj } from "@storybook/react-vite";
import { userEvent, within } from "storybook/test";
import { accessMeta } from "./accessMeta";

const meta = { ...accessMeta, title: "Vxpipe/Console/Authentication/Sign in", args: { ...accessMeta.args, initialPath: "/auth/login" } } satisfies Meta<typeof accessMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Setup: Story = { args: { initialPath: "/auth/setup" } };
export const SuperadminStep: Story = { args: { initialPath: "/auth/setup" }, play: async ({ canvasElement }) => {
  await userEvent.click(within(canvasElement).getByRole("button", { name: /Continue/ }));
} };
export const SetupSaveFailure: Story = { args: { initialPath: "/auth/setup", saveBehavior: "failure" } };
export const SetupSaving: Story = { args: { initialPath: "/auth/setup", saveBehavior: "pending" } };
export const SetupLight: Story = { args: { initialPath: "/auth/setup", theme: "light" } };
export const Login: Story = { args: { initialPath: "/auth/login" } };
export const Recovery: Story = { args: { initialPath: "/auth/recover" } };
