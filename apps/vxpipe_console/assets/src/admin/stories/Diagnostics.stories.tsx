import type { Meta, StoryObj } from "@storybook/react-vite";
import { workspaceMeta } from "./workspaceMeta";

const meta = { ...workspaceMeta, title: "Vxpipe/Console/Diagnostics/Diagnostics", args: { ...workspaceMeta.args, initialPath: "/diagnostics" } } satisfies Meta<typeof workspaceMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Diagnostics: Story = { args: { initialPath: "/diagnostics" } };
