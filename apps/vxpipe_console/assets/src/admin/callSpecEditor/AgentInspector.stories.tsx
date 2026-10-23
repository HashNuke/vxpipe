import { toolCatalogFixture } from "./toolCatalogFixture";
import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { EditorTheme } from "./EditorTheme";
import { AgentInspector, type AgentInspectorTab } from "./agent-inspector";
import { editorStoryFixture as editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import type { SourceDocument } from "./types";
import { validateSource } from "./validation";
import { recommendedSelection } from "./seed";
import "../admin.css";

type Props = { theme: "light" | "dark"; initial: SourceDocument; initialTab: AgentInspectorTab };
function AgentInspectorStory({ theme, initial, initialTab }: Props) {
  const [document, onChange] = useState(initial);
  const [participantKey, onRenamed] = useState("intake");
  const [tab, onTabChange] = useState(initialTab);
  return <EditorTheme theme={theme}><main className="min-h-screen bg-muted p-0 sm:p-6"><div className="mx-auto h-dvh min-h-[32rem] w-full max-w-[34rem] overflow-hidden border border-border bg-background sm:h-[calc(100dvh-3rem)] sm:rounded-md">
    {Object.hasOwn(document.source.participants, participantKey) ? <AgentInspector document={document} onChange={onChange} issues={validateSource(document.source)} catalog={modelCatalogFixture} lookups={{ telephonyServices: [], credentialNames: { deepgram: ["production"] }, mcpIntegrations: ["calendar", "support"], toolCatalog: toolCatalogFixture }} participantKey={participantKey} onRenamed={onRenamed} tab={tab} onTabChange={onTabChange} /> : <p className="p-4 text-sm text-muted-foreground">Participant removed.</p>}
  </div></main></EditorTheme>;
}
const initial = structuredClone(editorFixture);
initial.source.defaults = { capabilities: { model_inference: { provider: "google", model: "gemini-2.5-flash" }, text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "hannah" } } } };
initial.source.participants.reviewer = { type: "agent", prompt: "Help with billing questions.", description: "Billing specialist" };
const voice = structuredClone(initial);
voice.source.participants.intake!.capabilities = { text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "haley" } } };
const speechToSpeech = structuredClone(initial);
speechToSpeech.source.defaults = { capabilities: { speech_to_speech: recommendedSelection(modelCatalogFixture, "speech_to_speech", "google") } };
const fixed = structuredClone(initial);
if (fixed.source.participants.intake?.type === "agent") fixed.source.participants.intake.first_message = { mode: "fixed", text: "Hello, how can I help you today?" };
const tools = structuredClone(initial);
if (tools.source.participants.intake?.type === "agent") tools.source.participants.intake.tools = {
  get_current_time: { type: "platform", tool: "get_current_time" },
  calendar__find_slots: { type: "mcp", integration: "calendar", tool: "find_slots", conversation_mode: "non_blocking" },
  hangup: { type: "platform", tool: "hangup" },
};
const history = structuredClone(initial);
if (history.source.participants.intake?.type === "agent") history.source.participants.intake.transfer_history = { mode: "last_n_spoken", turns: 3 };
const meta = {
  title: "Vxpipe/Console/Call spec editor/components/Agent inspector",
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
  const destinations = within(await canvas.findByRole("region", { name: "Allowed destinations" }));
  await expect(destinations.getByText("specialist")).toBeInTheDocument();
  await expect(destinations.queryByText("Human destination")).not.toBeInTheDocument();
  await expect(canvas.findByRole("button", { name: "Add destination" })).resolves.toBeInTheDocument();
} };
export const VoiceAndModel: Story = { name: "Models", args: { initialTab: "voice", initial: voice } };
export const SpeechToSpeech: Story = { args: { initialTab: "voice", initial: speechToSpeech } };
export const FixedFirstMessage: Story = { args: { initial: fixed } };
export const Tools: Story = { args: { initialTab: "tools", initial: tools } };
export const Presence: Story = { name: "Media", args: { initialTab: "presence" } };
export const ReadOnly: Story = { args: { initial: { ...fixed, readOnly: true } } };
export const AddToolSource: Story = { args: { initialTab: "tools", initial: tools }, play: async ({ canvasElement }) => {
  await userEvent.click(await within(canvasElement).findByRole("button", { name: "Add tool" }));
  await expect(within(canvasElement.ownerDocument.body).findByRole("dialog")).resolves.toBeInTheDocument();
} };
export const AddToolOptions: Story = { args: { initialTab: "tools", initial: tools }, play: async ({ canvasElement }) => {
  await userEvent.click(await within(canvasElement).findByRole("button", { name: "Edit calendar__find_slots" }));
  await expect(within(canvasElement.ownerDocument.body).findByRole("combobox", { name: "Conversation mode" })).resolves.toHaveTextContent("Non-blocking");
} };

export const McpToolSelection: Story = { args: { initialTab: "tools", initial: tools }, play: async ({ canvasElement }) => {
  await userEvent.click(await within(canvasElement).findByRole("button", { name: "Add tool" }));
  const page = within(canvasElement.ownerDocument.body);
  await userEvent.click(await page.findByRole("button", { name: "calendar" }));
  await userEvent.click(await page.findByRole("checkbox", { name: "book_slot" }));
  await expect(page.findByRole("button", { name: "Add 1 tool" })).resolves.toBeEnabled();
} };

export const McpAllTools: Story = { args: { initialTab: "tools", initial: tools }, play: async ({ canvasElement }) => {
  await userEvent.click(await within(canvasElement).findByRole("button", { name: "Add tool" }));
  const page = within(canvasElement.ownerDocument.body);
  await userEvent.click(await page.findByRole("button", { name: "calendar" }));
  await userEvent.click(await page.findByRole("checkbox", { name: "Include all tools" }));
  await userEvent.click(await page.findByRole("checkbox", { name: "Non-blocking book_slot" }));
  await expect(page.queryByRole("combobox", { name: "Conversation mode" })).not.toBeInTheDocument();
  await expect(page.findByRole("button", { name: "Add 17 tools" })).resolves.toBeEnabled();
} };
