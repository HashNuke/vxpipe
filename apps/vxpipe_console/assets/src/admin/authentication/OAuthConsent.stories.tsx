import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { OAuthConsentStory } from "./OAuthConsentStory";

const meta = {
  title: "Vxpipe/Console/Authentication/MCP authorization",
  component: OAuthConsentStory,
  args: { theme: "dark", initialStep: "consent", clientKind: "cimd", branding: "provided", access: "assigned", longContent: false },
  argTypes: {
    theme: { control: "select", options: ["dark", "light"] },
    initialStep: { control: "select", options: ["consent", "unavailable"] },
    clientKind: { control: "select", options: ["cimd", "dcr"] },
    branding: { control: "select", options: ["provided", "missing", "broken"] },
    access: { control: "select", options: ["assigned", "all-tenants", "empty"] },
  },
  parameters: {
    layout: "fullscreen",
    docs: { description: { component: "Shared production consent and recovery presentation. Codex branding uses public CIMD metadata; account, tenant and permissions are fixtures. Decisions return directly to the validated client callback in the same tab. Storybook simulates the decisions and return to the client in one canvas without authorization requests or external navigation." } },
  },
  render: (args) => <OAuthConsentStory key={JSON.stringify(args)} {...args} />,
} satisfies Meta<typeof OAuthConsentStory>;
export default meta;
type Story = StoryObj<typeof meta>;

export const ReviewRequest: Story = {};
export const AllowFlow: Story = { play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await userEvent.click(canvas.getByRole("button", { name: "Allow connection" }));
  await expect(canvas.getByRole("status")).toBeVisible();
} };
export const DenyFlow: Story = { play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await userEvent.click(canvas.getByRole("button", { name: "Deny" }));
  await expect(canvas.getByRole("status")).toBeVisible();
} };
export const DcrWithoutBranding: Story = { name: "DCR · no optional branding", args: { clientKind: "dcr" } };
export const MissingLogo: Story = { args: { branding: "missing" } };
export const BrokenLogo: Story = { args: { branding: "broken" } };
export const AllTenants: Story = { args: { access: "all-tenants" } };
export const NoPermissions: Story = { args: { access: "empty" } };
export const RequestUnavailable: Story = { args: { initialStep: "unavailable" } };
export const LongClientName: Story = { args: { longContent: true } };
export const Light: Story = { args: { theme: "light" } };
