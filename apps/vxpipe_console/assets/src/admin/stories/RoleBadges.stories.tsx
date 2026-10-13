import type { Meta, StoryObj } from "@storybook/react-vite";
import { accessComponentsMeta } from "./accessComponentsMeta";

const meta = { ...accessComponentsMeta, title: "Vxpipe/Console/shared/Role badges" } satisfies Meta<typeof accessComponentsMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const RoleBadges: Story = { args: { component: "badges" } };
