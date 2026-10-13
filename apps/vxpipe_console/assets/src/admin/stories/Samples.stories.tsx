import type { Meta, StoryObj } from "@storybook/react-vite";
import { workspaceMeta } from "./workspaceMeta";

const meta = { ...workspaceMeta, title: "Vxpipe/Console/Samples/Consoles" } satisfies Meta<typeof workspaceMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const VoiceSample: Story = { args: { initialPath: "/samples/voice" } };
export const TransferSample: Story = { args: { initialPath: "/samples/transfer" } };
