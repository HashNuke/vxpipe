import { NavigationJourney } from "../navigation/NavigationJourney";
import { tenants } from "../authentication/fixtures";
const tenant = `/t/${tenants[0].key}`;
import type { Meta, StoryObj } from "@storybook/react-vite";
import { setupMeta } from "./setupMeta";

const meta = { ...setupMeta, title: "Vxpipe/Console/Services/Tenant services" } satisfies Meta<typeof setupMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const ChooseServices: Story = {};
export const CreatingTenant: Story = { args: { scenario: "creating-tenant" } };
export const EnterCredentials: Story = {
  args: { scenario: "enter-credentials" },
};
export const Validating: Story = { args: { scenario: "validating" } };
export const ValidationError: Story = {
  args: { scenario: "validation-error" },
};
export const ProviderUnavailable: Story = {
  args: { scenario: "provider-unavailable" },
};
export const SpeechConnected: Story = {
  args: { scenario: "speech-connected" },
};
export const ReadyForSamples: Story = {
  args: { scenario: "ready-for-samples" },
};
export const MultipleProviders: Story = {
  args: { scenario: "multiple-providers" },
};
export const Rime: Story = { args: { scenario: "rime" } };
export const Unavailable: Story = { args: { scenario: "unavailable" } };
export const RenamedTenant: Story = { args: { scenario: "renamed-tenant" } };
export const TelnyxCredentials: Story = {
  args: { scenario: "telnyx-credentials" },
};
export const NewTenantSetup: Story = { args: { scenario: "new-tenant-setup" } };
export const ServicePicker: Story = { args: { scenario: "service-picker" } };
export const TelnyxAiOnly: Story = { args: { scenario: "telnyx-ai-only" } };
export const TelnyxConnected: Story = {
  args: { scenario: "telnyx-connected" },
};
export const InheritedServices: Story = {
  args: { scenario: "inherited-services" },
};
export const TenantOverride: Story = { args: { scenario: "tenant-override" } };
export const TenantOverrideError: Story = {
  args: { scenario: "tenant-override-error" },
};
export const Light: Story = { args: { theme: "light" } };
export const Narrow: Story = {
  globals: { viewport: { value: "390px-844px", isRotated: false } },
};
export const ReadOnlyServicesAndCredentials: Story = { render: args => <NavigationJourney theme={args.theme} {...{ persona: "service-reader", initialPath: `${tenant}/services` }} /> };
export const ReadOnlyTenantServices: Story = { render: args => <NavigationJourney theme={args.theme} {...{ persona: "service-reader", initialPath: `${tenant}/services` }} /> };
