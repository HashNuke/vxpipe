import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { accessMeta } from "./accessMeta";
import { AuthenticationStory } from "./AuthenticationStory";

const meta = {
  ...accessMeta,
  title: "Vxpipe/Console/My account/Connected clients",
  args: { ...accessMeta.args, initialPath: "/account/connections", connectionsScenario: "connected" },
  argTypes: { ...accessMeta.argTypes, connectionsScenario: { control: "select", options: ["connected", "empty", "loading", "unavailable", "revoke-failure", "revoking"] } },
  parameters: { docs: { description: { component: "Connected clients and revocation with an in-memory API adapter. Uses the production ConnectedClients component. A standalone page is proposed here; production currently exposes this section inside My account. No real credentials are revoked." } } },
  render: (args) => <AuthenticationStory key={JSON.stringify(args)} {...args} />,
} satisfies Meta<typeof AuthenticationStory>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Connected: Story = {};
export const RevokeAccess: Story = { play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await userEvent.click(await canvas.findByRole("button", { name: "Revoke access for Codex" }));
  await expect(await canvas.findByRole("status")).toHaveTextContent("Access revoked for Codex");
} };
export const Empty: Story = { args: { connectionsScenario: "empty" } };
export const Loading: Story = { args: { connectionsScenario: "loading" } };
export const LoadFailure: Story = { args: { connectionsScenario: "unavailable" } };
export const RevokeFailure: Story = { args: { connectionsScenario: "revoke-failure" }, play: async ({ canvasElement }) => {
  await userEvent.click(await within(canvasElement).findByRole("button", { name: "Revoke access for Codex" }));
} };
export const Revoking: Story = { args: { connectionsScenario: "revoking" }, play: async ({ canvasElement }) => {
  await userEvent.click(await within(canvasElement).findByRole("button", { name: "Revoke access for Codex" }));
} };
export const Light: Story = { args: { theme: "light" } };
