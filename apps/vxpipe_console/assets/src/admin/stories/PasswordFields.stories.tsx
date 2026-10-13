import type { Meta, StoryObj } from "@storybook/react-vite";
import { accessComponentsMeta } from "./accessComponentsMeta";

const meta = { ...accessComponentsMeta, title: "Vxpipe/Console/shared/Password fields" } satisfies Meta<typeof accessComponentsMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const PasswordAndConfirmation: Story = {};
