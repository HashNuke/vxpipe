import type { Meta, StoryObj } from "@storybook/react-vite";
import { GuardrailCallDetails } from "./GuardrailCallDetails";
import { scenarios } from "./guardrailInspectionFixtures";

const meta = {
  title: "Vxpipe/Console/Calls/History/Guardrails",
  component: GuardrailCallDetails,
  parameters: { layout: "fullscreen" },
  args: { scenario: "blocked-input", theme: "dark" },
  argTypes: { scenario: { control: "select", options: scenarios }, theme: { control: "select", options: ["dark", "light"] } },
} satisfies Meta<typeof GuardrailCallDetails>;
export default meta;
type Story = StoryObj<typeof meta>;
export const BlockedInput: Story = {};
export const MixedProposal: Story = { args: { scenario: "mixed-proposal" } };
export const TransferCheckBlocked: Story = { args: { scenario: "transfer-check-blocked" } };
export const BeforeAndAfter: Story = { args: { scenario: "before-and-after" } };
export const Passed: Story = { args: { scenario: "pass" } };
export const RepairAndTransfer: Story = { args: { scenario: "repair-and-transfer" } };
export const TransferDenied: Story = { args: { scenario: "transfer-denied" } };
export const PartialAnswer: Story = { args: { scenario: "partial-answer" } };
export const RestrictedHistory: Story = { args: { scenario: "restricted-history" } };
export const MultipleAgents: Story = { args: { scenario: "multiple-agents" } };
export const MissingUsage: Story = { args: { scenario: "missing-usage", initialTab: "Metrics" } };
