import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { OAuthConsentStory } from "./OAuthConsentStory";

const meta = {
  title: "Vxpipe/Console/Authentication/MCP authorization",
  component: OAuthConsentStory,
  args: { theme: "dark", initialStep: "consent", clientKind: "cimd", branding: "provided", access: "assigned", longContent: false },
  argTypes: {
    theme: { control: "select", options: ["dark", "light"] },
    initialStep: { control: "select", options: ["consent", "allowed", "denied", "unavailable"] },
    clientKind: { control: "select", options: ["cimd", "dcr"] },
    branding: { control: "select", options: ["provided", "missing", "broken"] },
    access: { control: "select", options: ["assigned", "all-tenants", "empty"] },
  },
  parameters: {
    layout: "fullscreen",
    docs: { description: { component: "Design proposal for /oauth/authorize/:id and its completion experience. Codex branding uses the supplied CIMD document; account, tenant and permissions are fixtures. Allow and Deny lead to proposed product screens with account and revocation navigation. Production currently responds with a 302 to the client callback; it does not serve these completion screens. The client owns its callback UI. No real authorization or redirects are performed. Optional logo_uri/client_uri branding also needs production wiring." } },
  },
  render: (args) => <OAuthConsentStory key={JSON.stringify(args)} {...args} />,
} satisfies Meta<typeof OAuthConsentStory>;
export default meta;
type Story = StoryObj<typeof meta>;

export const ReviewRequest: Story = {};
export const AllowFlow: Story = { play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await userEvent.click(canvas.getByRole("button", { name: "Allow connection" }));
  await expect(canvas.getByRole("heading", { name: "Access approved" })).toBeVisible();
} };
export const DenyFlow: Story = { play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await userEvent.click(canvas.getByRole("button", { name: "Deny" }));
  await expect(canvas.getByRole("heading", { name: "Connection declined" })).toBeVisible();
} };
export const DcrWithoutBranding: Story = { name: "DCR · no optional branding", args: { clientKind: "dcr" } };
export const MissingLogo: Story = { args: { branding: "missing" } };
export const BrokenLogo: Story = { args: { branding: "broken" } };
export const AllTenants: Story = { args: { access: "all-tenants" } };
export const NoPermissions: Story = { args: { access: "empty" } };
export const RequestUnavailable: Story = { args: { initialStep: "unavailable" } };
export const LongClientName: Story = { args: { longContent: true } };
export const Light: Story = { args: { theme: "light" } };
