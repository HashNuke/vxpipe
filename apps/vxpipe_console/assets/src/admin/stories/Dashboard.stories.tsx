import type { Meta, StoryObj } from "@storybook/react-vite";
import { workspaceMeta } from "./workspaceMeta";

const meta = { ...workspaceMeta, title: "Vxpipe/Console/Tenants/Dashboard" } satisfies Meta<typeof workspaceMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Dashboard: Story = {};
export const SingleTenantLogin: Story = { args: { persona: "single", initialPath: "/" } };
export const MixedPermissions: Story = { args: { persona: "mixed", initialPath: "/t/demo_tenant_0001/dashboard" } };
export const ReadOnlyMember: Story = { args: { persona: "member" } };
export const EmptyDashboard: Story = { args: { state: "empty" } };
export const LoadingDashboard: Story = { args: { state: "loading" } };
export const UnavailableDashboard: Story = { args: { state: "unavailable" } };
export const LightDashboard: Story = { args: { theme: "light" } };
