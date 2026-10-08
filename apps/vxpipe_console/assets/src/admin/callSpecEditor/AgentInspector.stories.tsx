import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { EditorTheme } from "./EditorTheme";
import { AgentInspector, type AgentInspectorTab } from "./agent-inspector";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import type { SourceDocument } from "./types";
import { validateSource } from "./validation";
import "../admin.css";

type Props = { theme: "light" | "dark"; initial: SourceDocument; initialTab: AgentInspectorTab };
function AgentInspectorStory({ theme, initial, initialTab }: Props) {
  const [document, onChange] = useState(initial);
  const [participantKey, onRenamed] = useState("intake");
  const [tab, onTabChange] = useState(initialTab);
  return <EditorTheme theme={theme}><main className="min-h-screen bg-muted p-0 sm:p-6"><div className="mx-auto h-dvh min-h-[32rem] w-full max-w-[34rem] overflow-hidden border border-border bg-background sm:h-[calc(100dvh-3rem)] sm:rounded-md">
    {Object.hasOwn(document.source.participants, participantKey) ? <AgentInspector document={document} onChange={onChange} issues={validateSource(document.source)} catalog={modelCatalogFixture} lookups={{ telephonyServices: [], credentialNames: { deepgram: ["production"] }, mcpIntegrations: ["calendar", "support"] }} participantKey={participantKey} onRenamed={onRenamed} tab={tab} onTabChange={onTabChange} /> : <p className="p-4 text-sm text-muted-foreground">Participant removed.</p>}
  </div></main></EditorTheme>;
}
const initial = structuredClone(editorFixture);
initial.source.defaults = { capabilities: { model_inference: { provider: "google", model: "gemini-2.5-flash" }, text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "hannah" } } } };
initial.source.participants.reviewer = { type: "agent", prompt: "Help with billing questions.", description: "Billing specialist" };
const voice = structuredClone(initial);
voice.source.participants.intake!.capabilities = { text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "haley" } } };
const fixed = structuredClone(initial);
if (fixed.source.participants.intake?.type === "agent") fixed.source.participants.intake.first_message = { mode: "fixed", text: "Hello, how can I help you today?" };
const tools = structuredClone(initial);
if (tools.source.participants.intake?.type === "agent") tools.source.participants.intake.tools = {
  availability: { type: "host", tool: "availability" },
  calendar_slots: { type: "mcp", integration: "calendar", tool: "find_slots", conversation_mode: "non_blocking" },
  finish: { type: "platform", tool: "hangup" },
};
const history = structuredClone(initial);
if (history.source.participants.intake?.type === "agent") history.source.participants.intake.transfer_history = { mode: "last_n_spoken", turns: 3 };
const meta = {
  title: "Vxpipe/Console/Call spec editor/Agent inspector",
  component: AgentInspectorStory,
  parameters: { layout: "fullscreen" },
  args: { theme: "dark", initial, initialTab: "prompt" },
  argTypes: { theme: { control: "select", options: ["dark", "light"] } },
} satisfies Meta<typeof AgentInspectorStory>;
export default meta;
type Story = StoryObj<typeof meta>;
// Adapted from the committed Callpipe component and page stories.
export const AgentInspectorDefault: Story = { play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await expect(canvas.findByLabelText("Participant key")).resolves.toHaveValue("intake");
  await expect(canvas.findByRole("tab", { name: "Variables" })).resolves.toBeInTheDocument();
} };
export const AgentVariables: Story = { args: { initialTab: "variables" }, play: async ({ canvasElement }) => {
  await expect(within(canvasElement).findByRole("combobox", { name: "appointment access for intake" })).resolves.toHaveTextContent("Read and write");
} };
export const AgentTransfers: Story = { args: { initialTab: "transfers", initial: history }, play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await expect(canvas.findByText("Appointment specialist")).resolves.toBeInTheDocument();
  await expect(canvas.findByRole("button", { name: "Add destination" })).resolves.toBeInTheDocument();
} };
export const VoiceAndModel: Story = { args: { initialTab: "voice", initial: voice } };
export const FixedFirstMessage: Story = { args: { initial: fixed } };
export const Tools: Story = { args: { initialTab: "tools", initial: tools } };
export const Presence: Story = { args: { initialTab: "presence" } };
export const ReadOnly: Story = { args: { initial: { ...fixed, readOnly: true } } };
export const AddToolSource: Story = { args: { initialTab: "tools", initial: tools }, play: async ({ canvasElement }) => {
  await userEvent.click(await within(canvasElement).findByRole("button", { name: "Add tool" }));
  await expect(within(canvasElement.ownerDocument.body).findByRole("dialog")).resolves.toBeInTheDocument();
} };
export const AddToolOptions: Story = { args: { initialTab: "tools", initial: tools }, play: async ({ canvasElement }) => {
  await userEvent.click(await within(canvasElement).findByRole("button", { name: "Edit calendar_slots" }));
  await expect(within(canvasElement.ownerDocument.body).findByRole("textbox", { name: "Local tool key" })).resolves.toHaveValue("calendar_slots");
} };
