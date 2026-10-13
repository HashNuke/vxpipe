import type { Meta, StoryObj } from "@storybook/react-vite";
import { workspaceMeta } from "./workspaceMeta";

const meta = { ...workspaceMeta, title: "Vxpipe/Console/Tenants/Getting started", args: { ...workspaceMeta.args, initialPath: "/getting-started" } } satisfies Meta<typeof workspaceMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const GettingStarted: Story = { args: { initialPath: "/getting-started" } };
