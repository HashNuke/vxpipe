import type { Meta, StoryObj } from "@storybook/react-vite";
import { workspaceMeta } from "./workspaceMeta";

const meta = { ...workspaceMeta, title: "Vxpipe/Console/Tenants/My tenants", args: { ...workspaceMeta.args, initialPath: "/tenants", persona: "multiple" } } satisfies Meta<typeof workspaceMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const MyTenants: Story = { args: { initialPath: "/tenants", persona: "multiple" } };
export const MultipleTenantLogin: Story = { args: { persona: "multiple", initialPath: "/" } };
export const NoTenantAccess: Story = { args: { persona: "none", initialPath: "/" } };
export const LoadingTenants: Story = { args: { initialPath: "/tenants", persona: "multiple", state: "loading" } };
export const UnavailableTenants: Story = { args: { initialPath: "/tenants", persona: "multiple", state: "unavailable" } };
