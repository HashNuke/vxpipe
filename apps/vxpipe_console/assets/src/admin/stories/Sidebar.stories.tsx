import type { Meta, StoryObj } from "@storybook/react-vite";
import { useState } from "react";
import { NavigationShell } from "../navigation/NavigationShell";
import { tenants, users, roles } from "../authentication/fixtures";
function SidebarStory({ selected = true, settings = false, theme = "dark", pickerState = "ready" }: { selected?: boolean; settings?: boolean; theme?: "dark" | "light"; pickerState?: "ready" | "loading" | "unavailable" }) {
  const [path, setPath] = useState(settings ? "/roles" : selected ? `/t/${tenants[0].key}/calls` : "/tenants");
  const [state, setState] = useState(pickerState);
  return <NavigationShell role={roles[0]} user={users[0]} tenants={tenants} selected={tenants.find(tenant => path.startsWith(`/t/${tenant.key}/`))} path={path} onNavigate={setPath} onLogout={() => setPath("/auth/login")} theme={theme} pickerState={state} onRetry={() => setState("ready")}><main /></NavigationShell>;
}
const meta = { title: "Vxpipe/Console/shared/Sidebar", component: SidebarStory, args: { selected: true, theme: "dark", pickerState: "ready" }, render: args => <SidebarStory key={`${args.selected}-${args.settings}-${args.theme}-${args.pickerState}`} {...args} /> } satisfies Meta<typeof SidebarStory>;
export default meta;
type Story = StoryObj<typeof meta>;
export const SelectedTenant: Story = {};
export const NoSelection: Story = { args: { selected: false } };
export const LoadingTenants: Story = { args: { pickerState: "loading" } };
export const UnavailableTenants: Story = { args: { pickerState: "unavailable" } };
export const Light: Story = { args: { theme: "light" } };

export const Settings: Story = { args: { settings: true } };
