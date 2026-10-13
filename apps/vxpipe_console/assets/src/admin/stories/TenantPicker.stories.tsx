import type { Meta, StoryObj } from "@storybook/react-vite";
import { useState } from "react";
import { AdminShell } from "../AdminShell";
import { TenantPicker } from "../navigation/TenantPicker";
import { tenants } from "../authentication/fixtures";
function TenantPickerStory({ theme = "dark", state = "ready" }: { theme?: "dark" | "light"; state?: "ready" | "loading" | "unavailable" }) {
  const [selected, setSelected] = useState(tenants[0]);
  const [phase, setPhase] = useState(state);
  return <AdminShell theme={theme} showHeader={false}><div className="w-64 p-4"><TenantPicker tenants={tenants} selected={selected} directoryPath="/tenants" state={phase} onRetry={() => setPhase("ready")} onNavigate={path => setSelected(tenants.find(tenant => path === `/t/${tenant.key}/dashboard`) ?? selected)} /></div></AdminShell>;
}
const meta = { title: "Vxpipe/Console/shared/Tenant picker", component: TenantPickerStory, args: { theme: "dark", state: "ready" }, render: args => <TenantPickerStory key={`${args.theme}-${args.state}`} {...args} /> } satisfies Meta<typeof TenantPickerStory>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Search: Story = {};
export const Loading: Story = { args: { state: "loading" } };
export const Unavailable: Story = { args: { state: "unavailable" } };
export const Light: Story = { args: { theme: "light" } };
