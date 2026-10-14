import type { Meta, StoryObj } from "@storybook/react-vite";
import { NavigationJourney } from "./NavigationJourney";

const meta = { title: "Vxpipe/Console/Tenants/Create", component: NavigationJourney, parameters: { layout: "fullscreen" }, args: { initialPath: "/tenants/new" } } satisfies Meta<typeof NavigationJourney>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
export const NoPermission: Story = { args: { persona: "member" } };

export const CreationError: Story = { args: { creationOutcome: "error" } };
export const Submitting: Story = { args: { creationOutcome: "pending" } };
export const MetadataOnly: Story = { args: { identity: {
  role: { id: "creator", name: "Tenant creator", kind: null, grants: [{ permission: "tenants.write", scope: "installation" }] },
  user: { id: "creator", email: "creator@example.test", enabled: true, roleId: "creator", memberships: [] },
} } };
