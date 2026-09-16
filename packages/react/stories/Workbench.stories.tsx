import type { Meta, StoryObj } from "@storybook/react-vite";
import { Workbench } from "./Workbench.js";

const meta = {
  title: "Prototype/Workbench",
  component: Workbench,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Interactive UI prototype with synthetic data. No network calls, audio playback or microphone capture. Change scenarios, themes and fixture timing through Storybook Controls.",
      },
    },
  },
  args: {
    theme: "dark",
    scenario: "conversation",
    ready: true,
    animateSpeech: false,
    page: "console",
    initialTab: "chat",
  },
  render: (args) => (
    <Workbench
      key={`${args.theme}-${args.scenario}-${args.page}-${args.ready}-${args.initialTab}`}
      {...args}
    />
  ),
  argTypes: {
    theme: { control: "select", options: ["light", "dark"] },
    scenario: {
      control: "select",
      options: [
        "ready",
        "conversation",
        "handoff",
        "human-handoff",
        "microphone-denied",
        "no-alignment",
        "ended",
        "failed",
      ],
    },
    page: { control: "select", options: ["console", "setup"] },
    initialTab: { control: "select", options: ["chat", "metrics", "logs"] },
    animateSpeech: {
      control: "boolean",
      description: "Animate fixture word timing without playing audio.",
    },
  },
} satisfies Meta<typeof Workbench>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Conversation: Story = {};
export const ReadyToStart: Story = { args: { scenario: "ready" } };
export const AgentHandoff: Story = { args: { scenario: "handoff" } };
export const HumanHandoff: Story = { args: { scenario: "human-handoff" } };
export const Metrics: Story = { args: { initialTab: "metrics" } };
export const RtviEvents: Story = { args: { initialTab: "logs" } };
export const MicrophoneDenied: Story = {
  args: { scenario: "microphone-denied" },
};
export const NoWordTiming: Story = { args: { scenario: "no-alignment" } };
export const Ended: Story = { args: { scenario: "ended" } };
export const ConnectionFailed: Story = { args: { scenario: "failed" } };
export const Light: Story = { args: { theme: "light" } };
export const SetupIncomplete: Story = { args: { page: "setup", ready: false } };
export const SetupComplete: Story = { args: { page: "setup", ready: true } };
