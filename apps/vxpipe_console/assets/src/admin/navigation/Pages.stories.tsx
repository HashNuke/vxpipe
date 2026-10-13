import type { Meta, StoryObj } from "@storybook/react-vite";
import { NavigationJourney } from "./NavigationJourney";
import { tenants, users, roles } from "../authentication/fixtures";
const tenant = `/t/${tenants[0].key}`;
const meta = {
  title: "Vxpipe/Console/Navigation/Pages", component: NavigationJourney,
  args: { persona: "all", theme: "dark", initialPath: `${tenant}/dashboard`, state: "ready", pickerState: "ready" },
  argTypes: { persona: { control: "select", options: ["all", "single", "multiple", "member", "mixed", "none", "keys-only", "platform-reader", "service-reader"] }, theme: { control: "select", options: ["dark", "light"] }, state: { control: "select", options: ["ready", "loading", "unavailable", "empty"] }, pickerState: { control: "select", options: ["ready", "loading", "unavailable"] } },
  parameters: { docs: { description: { component: "Navigation and dashboard reference stories. Synthetic fixtures only; no backend calls. Permission profiles model the implemented authorization contract; the Console uses production routes and scoped APIs. Story links stay inside this fixture journey; specialized editors/inspectors stay standalone." } } },
  render: args => <NavigationJourney key={`${args.persona}-${args.theme}-${args.initialPath}-${args.state}-${args.pickerState}`} {...args} />,
} satisfies Meta<typeof NavigationJourney>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Dashboard: Story = {};
export const AllTenantLogin: Story = { args: { initialPath: "/" } };
export const SingleTenantLogin: Story = { args: { persona: "single", initialPath: "/" } };
export const MultipleTenantLogin: Story = { args: { persona: "multiple", initialPath: "/" } };
export const NoTenantAccess: Story = { args: { persona: "none", initialPath: "/" } };
export const MixedPermissions: Story = { args: { persona: "mixed", initialPath: "/t/demo_tenant_0001/dashboard" } };
export const ReadOnlyMember: Story = { args: { persona: "member" } };
export const Tenants: Story = { args: { initialPath: "/tenants" } };
export const MyTenants: Story = { args: { initialPath: "/my-tenants", persona: "multiple" } };
export const Calls: Story = { args: { initialPath: `${tenant}/calls` } };
export const CallSpecs: Story = { args: { initialPath: `${tenant}/call-specs` } };
export const Services: Story = { args: { initialPath: `${tenant}/services` } };
export const PlatformServices: Story = { args: { initialPath: "/platform/services" } };
export const Users: Story = { args: { initialPath: "/users" } };
export const CreateUser: Story = { args: { initialPath: "/users/new" } };
export const UserDetails: Story = { args: { initialPath: `/users/${users[4].id}` } };
export const ResetPassword: Story = { args: { initialPath: `/users/${users[4].id}/reset-password` } };
export const Roles: Story = { args: { initialPath: "/roles" } };
export const CreateRole: Story = { args: { initialPath: "/roles/new" } };
export const RoleDetails: Story = { args: { initialPath: `/roles/${roles[2].id}` } };
export const BuiltInRole: Story = { args: { initialPath: `/roles/${roles[0].id}` } };
export const MyAccount: Story = { args: { initialPath: "/account" } };
export const GettingStarted: Story = { args: { initialPath: "/getting-started" } };
export const ApiKeys: Story = { args: { initialPath: `${tenant}/api-keys` } };
export const SampleCallSpecs: Story = { args: { initialPath: `${tenant}/samples` } };
export const CallHistory: Story = { args: { initialPath: `${tenant}/calls/example` } };
export const Login: Story = { args: { initialPath: "/auth/login" } };
export const Setup: Story = { args: { initialPath: "/auth/setup" } };
export const Recovery: Story = { args: { initialPath: "/auth/recover" } };
export const EmptyDashboard: Story = { args: { state: "empty" } };
export const LoadingDashboard: Story = { args: { state: "loading" } };
export const UnavailableDashboard: Story = { args: { state: "unavailable" } };
export const LoadingTenants: Story = { args: { initialPath: "/my-tenants", persona: "multiple", state: "loading" } };
export const UnavailableTenants: Story = { args: { initialPath: "/my-tenants", persona: "multiple", state: "unavailable" } };
export const PickerUnavailable: Story = { args: { pickerState: "unavailable" } };
export const LightDashboard: Story = { args: { theme: "light" } };

export const LegacyServices: Story = { args: { initialPath: `${tenant}/legacy-services` } };
export const CallSpecEditor: Story = { args: { initialPath: `${tenant}/editor` } };
export const Diagnostics: Story = { args: { initialPath: "/diagnostics" } };
export const VoiceSample: Story = { args: { initialPath: "/samples/voice" } };
export const TransferSample: Story = { args: { initialPath: "/samples/transfer" } };
export const ApiKeyOnlyServices: Story = { args: { persona: "keys-only", initialPath: `${tenant}/services` } };
export const ReadOnlyApiKeys: Story = { args: { persona: "keys-only", initialPath: `${tenant}/api-keys` } };
export const ReadOnlyPlatformServices: Story = { args: { persona: "platform-reader", initialPath: "/platform/services" } };
export const ReadOnlyTenantServices: Story = { args: { persona: "service-reader", initialPath: `${tenant}/services` } };
export const ReadOnlyLegacyServices: Story = { args: { persona: "service-reader", initialPath: `${tenant}/legacy-services` } };
