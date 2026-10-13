import type { Meta, StoryObj } from "@storybook/react-vite";
import { setupMeta } from "./setupMeta";

const meta = { ...setupMeta, title: "Vxpipe/Console/Tenants/Create tenant" } satisfies Meta<typeof setupMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const NewTenant: Story = { args: { scenario: "new-tenant" } };
export const CreatingNewTenant: Story = {
  args: { scenario: "creating-new-tenant" },
};
export const TenantCreationError: Story = {
  args: { scenario: "tenant-creation-error" },
};
