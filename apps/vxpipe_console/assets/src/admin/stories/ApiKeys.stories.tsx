import type { Meta, StoryObj } from "@storybook/react-vite";
import { ApiKeysStory } from "../apiKeys/ApiKeysStory";
const meta = { title: "Vxpipe/Console/API Keys", component: ApiKeysStory, parameters: { layout: "fullscreen",
  docs: { description: { component: "Settings API-key management. Storybook uses simulated paginated requests; the app uses permission-scoped backend APIs." } } },
  args: { theme: "dark", scenario: "existing" } } satisfies Meta<typeof ApiKeysStory>;
export default meta;
type Story = StoryObj<typeof meta>;
export const ExistingApiKey: Story = {};
export const CreateApiKeys: Story = { args: { initialCreating: true } };
export const FullTenantAccess: Story = { args: { initialCreating: true, initialKind: "full" } };
export const FullPlatformAccess: Story = { args: { initialCreating: true, initialKind: "platform" } };
export const TenantOnly: Story = { args: { tenantOnly: true } };
export const ReadOnlyApiKeys: Story = { args: { readOnly: true } };
export const Empty: Story = { args: { scenario: "empty" } };
export const Loading: Story = { args: { scenario: "loading" } };
export const Unavailable: Story = { args: { scenario: "unavailable" } };
export const CreatingApiKey: Story = { args: { scenario: "creating", initialCreating: true } };
export const ApiKeyError: Story = { args: { scenario: "error", initialCreating: true } };
export const Light: Story = { args: { theme: "light" } };
