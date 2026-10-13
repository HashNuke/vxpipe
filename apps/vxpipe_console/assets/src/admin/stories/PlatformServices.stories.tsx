import { NavigationJourney } from "../navigation/NavigationJourney";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { setupMeta } from "./setupMeta";

const meta = { ...setupMeta, title: "Vxpipe/Console/Services/Platform services" } satisfies Meta<typeof setupMeta.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const PlatformServices: Story = {
  args: { scenario: "platform-services" },
};
export const PlatformConfigured: Story = {
  args: { scenario: "platform-configured" },
};
export const PlatformTelnyx: Story = { args: { scenario: "platform-telnyx" } };
export const ReadOnlyPlatformServices: Story = { render: args => <NavigationJourney theme={args.theme} {...{ persona: "platform-reader", initialPath: "/platform/services" }} /> };
