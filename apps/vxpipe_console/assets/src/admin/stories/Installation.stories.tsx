import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { accessMeta } from "./accessMeta";

const meta = {
  ...accessMeta,
  title: "Vxpipe/Console/Settings/Installation",
  args: { ...accessMeta.args, initialPath: "/platform/installation" },
  parameters: { layout: "fullscreen", docs: { description: { component:
    "Installation URL workflow for review. Saves and permissions are simulated in memory; no backend changes, OAuth registrations or DNS changes occur. Reload to reset." } } },
} satisfies Meta<typeof accessMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

const proposeChange: NonNullable<Story["play"]> = async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await userEvent.clear(canvas.getByLabelText("Vxpipe URL"));
  await userEvent.type(canvas.getByLabelText("Vxpipe URL"), "https://voice.example.test");
  await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
  await expect(canvas.getByRole("dialog", { name: "Change Vxpipe URL?" })).toBeVisible();
};

export const Default: Story = {};
export const ChangeUrl: Story = { play: proposeChange };
export const SaveFailure: Story = { args: { saveBehavior: "failure" }, play: async context => {
  await proposeChange(context);
  const canvas = within(context.canvasElement);
  await userEvent.click(canvas.getByRole("button", { name: "Change URL" }));
  await expect(canvas.getByRole("alert")).toBeVisible();
} };
export const Saving: Story = { args: { saveBehavior: "pending" }, play: async context => {
  await proposeChange(context);
  await userEvent.click(within(context.canvasElement).getByRole("button", { name: "Change URL" }));
} };
export const NotConfigured: Story = { args: { initialPublicUrl: "" } };
export const AdminDenied: Story = { args: { actor: "admin" } };
export const MemberDenied: Story = { args: { actor: "member" } };
export const Loading: Story = { args: { state: "loading" } };
export const Unavailable: Story = { args: { state: "unavailable" } };
export const Light: Story = { args: { theme: "light" } };
