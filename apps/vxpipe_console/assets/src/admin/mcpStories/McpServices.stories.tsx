import type { Meta, StoryObj } from "@storybook/react-vite";
import { McpServicesStory } from "./McpServicesStory";
import { scenarios } from "./fixtures";

const meta = {
  title: "Vxpipe/Console/Services/MCP integrations",
  component: McpServicesStory,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Design preview only. Provider endpoints are documented; tool catalogs, accounts, checks and OAuth are simulated locally. No credentials are saved or transmitted. These components are not imported by production routes.",
      },
    },
  },
  args: { scenario: "services", theme: "dark" },
  argTypes: {
    scenario: { control: "select", options: scenarios },
    theme: { control: "select", options: ["dark", "light"] },
  },
  render: (args) => (
    <McpServicesStory key={`${args.scenario}-${args.theme}`} {...args} />
  ),
} satisfies Meta<typeof McpServicesStory>;
export default meta;
type Story = StoryObj<typeof meta>;
export const TenantServices: Story = { name: "Tenant Integrations" };
export const ConnectedIntegrations: Story = { args: { scenario: "connected" } };
export const TenantIntegrationManager: Story = { args: { scenario: "connected", canManagePlatform: false } };
export const ConnectService: Story = { args: { scenario: "picker" } };
export const ServiceDirectory: Story = { name: "Integrations", args: { scenario: "picker" } };
export const AIModels: Story = { args: { scenario: "directory-ai" } };
export const TelephonyServices: Story = {
  args: { scenario: "directory-telephony" },
};
export const Calendar: Story = { args: { scenario: "directory-calendar" } };
export const CRM: Story = { args: { scenario: "directory-crm" } };
export const OfficeSuite: Story = { args: { scenario: "directory-office" } };
export const ConnectGoogleAIStudio: Story = {
  args: { scenario: "connect-google" },
};
export const ConnectDeepgram: Story = {
  args: { scenario: "connect-deepgram" },
};
export const ConnectTelnyx: Story = { args: { scenario: "connect-telnyx" } };
export const ConnectTwilio: Story = { args: { scenario: "connect-twilio" } };
export const AlreadyConnectedAI: Story = { args: { scenario: "already-connected-ai" } };
export const AlreadyConnectedMCP: Story = { args: { scenario: "already-connected-mcp" } };
export const CustomMCP: Story = { args: { scenario: "custom" } };
export const RegistrationRequired: Story = { args: { scenario: "registration-required" } };
export const DiscoveryFailed: Story = { args: { scenario: "discovery-failed" } };
export const InstallationURLRequired: Story = { args: { scenario: "installation-url-required" } };
export const DiscoverNoAuthentication: Story = { args: { scenario: "discovery-no-auth" } };
export const ConnectedWithoutTools: Story = { args: { scenario: "connected-no-tools" } };
export const CalCom: Story = { args: { scenario: "calcom" } };
export const GoogleCalendar: Story = { args: { scenario: "google-calendar" } };
export const GoogleSheets: Story = { args: { scenario: "google-sheets" } };
export const GoogleDocs: Story = { args: { scenario: "google-docs" } };
export const HubSpot: Story = { args: { scenario: "hubspot" } };
export const Calendly: Story = { args: { scenario: "calendly" } };
export const ManualCIMD: Story = { args: { scenario: "cimd" } };
export const ManualDCR: Story = { args: { scenario: "dcr" } };
export const CustomOAuth: Story = { args: { scenario: "custom-oauth" } };
export const BearerToken: Story = { args: { scenario: "custom-bearer" } };
export const APIKeyAndHeaders: Story = { args: { scenario: "custom-headers" } };
export const BasicAuth: Story = { args: { scenario: "custom-basic" } };
export const NoAuthentication: Story = { args: { scenario: "no-auth" } };
export const Authorizing: Story = { args: { scenario: "authorizing" } };
export const CheckingConnection: Story = { args: { scenario: "checking" } };
export const ConnectionError: Story = {
  args: { scenario: "connection-error" },
};
export const ReconnectRequired: Story = { args: { scenario: "reconnect" } };
export const NoMCPConnections: Story = { args: { scenario: "empty" } };
export const ReadOnly: Story = { args: { scenario: "read-only" } };
export const Light: Story = { args: { scenario: "picker", theme: "light" } };
export const Mobile: Story = {
  args: { scenario: "custom-oauth" },
  globals: { viewport: { value: "390px-844px", isRotated: false } },
};

export const RemoteCategories: Story = { args: { scenario: "directory-expanded" } };
export const DirectoryLoading: Story = { args: { scenario: "directory-loading" } };
export const DirectoryUnavailable: Story = { args: { scenario: "directory-unavailable" } };
export const CachedDirectory: Story = { args: { scenario: "directory-stale" } };
export const CheckingSavedConnections: Story = { args: { scenario: "directory-connections-loading" } };
export const ConnectionStatusUnavailable: Story = { args: { scenario: "directory-connections-error" } };
export const DirectoryReconnectRequired: Story = { args: { scenario: "directory-reconnect" } };

export const PaginatedDirectory: Story = { args: { scenario: "directory-paginated" } };
export const LoadingDirectoryPage: Story = { args: { scenario: "directory-page-loading" } };
export const DirectoryPageError: Story = { args: { scenario: "directory-page-error" } };

export const VersionFilteredSearch: Story = { args: { scenario: "directory-search-versions" } };
