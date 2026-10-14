import { NavigationJourney } from "../navigation/NavigationJourney";
import { tenants } from "../authentication/fixtures";
const tenant = `/t/${tenants[0].key}`;
import type { Meta, StoryObj } from "@storybook/react-vite";
import { setupMeta } from "./setupMeta";

const meta = { ...setupMeta, title: "Vxpipe/Console/Services/API keys" } satisfies Meta<typeof setupMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const CreateApiKeys: Story = { args: { scenario: "api-keys" } };
export const FullTenantAccess: Story = {
  args: { scenario: "api-key-full-access" },
};
export const CreatingApiKey: Story = { args: { scenario: "api-key-creating" } };
export const ApiKeyError: Story = { args: { scenario: "api-key-error" } };
export const ApiKeyCreated: Story = { args: { scenario: "api-key-created" } };
export const ExistingApiKey: Story = { args: { scenario: "api-key-existing" } };
export const ReadOnlyApiKeys: Story = { render: args => <NavigationJourney theme={args.theme} {...{ persona: "service-reader", initialPath: `${tenant}/api-keys` }} /> };
