import type { Meta, StoryObj } from "@storybook/react-vite";
import { StoryProviderDialog } from "../mcpStories/StoryProviderDialog";
import "../mcpStories/mcp-services-story.css";
import type { CredentialTestResult } from "../serviceTypes";
import { StoryWorkspace } from "./StoryWorkspace";

const meta = {
  title: "Vxpipe/Console/Services/Morse API",
  component: StoryProviderDialog,
  parameters: {
    layout: "fullscreen",
    docs: { description: { component: "Morse service setup with simulated connection results. No provider requests are made." } },
  },
  args: {
    state: { provider: "morse_code_api", status: "idle" },
    scope: { kind: "platform" },
    onClose: () => undefined,
    onSubmit: () => undefined,
    onTest: async (): Promise<CredentialTestResult> => ({ status: "valid" }),
  },
  render: args => <StoryWorkspace path="/platform/services"><div className="mcp-services-preview"><StoryProviderDialog {...args} /></div></StoryWorkspace>,
} satisfies Meta<typeof StoryProviderDialog>;

export default meta;
type Story = StoryObj<typeof meta>;
export const Reachable: Story = {};
export const Unavailable: Story = {
  args: { onTest: async () => ({ status: "error", message: "Simulated unavailable endpoint" }) },
};
