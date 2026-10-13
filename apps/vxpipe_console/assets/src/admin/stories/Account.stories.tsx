import type { Meta, StoryObj } from "@storybook/react-vite";
import { accessMeta } from "./accessMeta";

const meta = { ...accessMeta, title: "Vxpipe/Console/My account/Account", args: { ...accessMeta.args, initialPath: "/account" } } satisfies Meta<typeof accessMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Account: Story = { args: { initialPath: "/account" } };
