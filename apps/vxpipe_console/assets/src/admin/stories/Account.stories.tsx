import type { Meta, StoryObj } from "@storybook/react-vite";
import { accessMeta } from "./accessMeta";

const meta = { ...accessMeta, title: "Vxpipe/Console/Settings/Your account", args: { ...accessMeta.args, initialPath: "/account" } } satisfies Meta<typeof accessMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Account: Story = { args: { initialPath: "/account" } };

export const Member: Story = { args: { actor: "member" } };
export const ChangePassword: Story = { play: async ({ canvasElement }) => {
  const { userEvent, within } = await import("storybook/test");
  await userEvent.click(within(canvasElement).getByRole("checkbox", { name: "Change password" }));
} };
