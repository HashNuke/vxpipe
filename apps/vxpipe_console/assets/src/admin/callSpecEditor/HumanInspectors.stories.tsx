import { storyPhoneNumbers } from "./phone-number-fixtures";
import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, within } from "storybook/test";
import { EditorTheme } from "./EditorTheme";
import { HumanInspector } from "./human-inspector";
import type { HumanInspectorTab } from "./human-inspector-tabs";
import { editorStoryFixture as editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import type { SourceDocument } from "./types";
import { validateSource } from "./validation";
import "../admin.css";

type Props = { theme: "light" | "dark"; initial: SourceDocument; initialTab?: HumanInspectorTab };
function HumanInspectorStory({ theme, initial, initialTab = "connection" }: Props) {
  const [document, onChange] = useState(initial);
  const [participantKey, onRenamed] = useState("specialist");
  const [tab, onTabChange] = useState(initialTab);
  const props = { document, onChange, issues: validateSource(document.source), catalog: modelCatalogFixture, lookups: { phoneNumbers: storyPhoneNumbers, telephonyServices: [{ key: "telnyx", name: "Telnyx", provider: "telnyx" as const }], credentialNames: { deepgram: ["production"] }, mcpIntegrations: [] }, tab, onTabChange };
  return <EditorTheme theme={theme}><main className="min-h-screen bg-muted p-0 sm:p-6"><div className="mx-auto h-dvh min-h-[32rem] w-full max-w-[34rem] overflow-hidden border border-border bg-background sm:h-[calc(100dvh-3rem)] sm:rounded-md">
    {Object.hasOwn(document.source.participants, participantKey) ? <HumanInspector {...props} participantKey={participantKey} onRenamed={onRenamed} /> : <p className="p-4 text-sm text-muted-foreground">Participant removed.</p>}
  </div></main></EditorTheme>;
}
const phone = structuredClone(editorFixture);
phone.source.participants.specialist = { type: "human", description: "Appointment specialist", connection: { service: "telnyx", mode: "dial", admission: "transfer", number: "+15550001000" }, transfer_notice: "Please help this caller with their appointment." };
const variable = structuredClone(phone);
variable.source.call_variables = { sections: { routing: { schema: { type: "object", properties: { support_phone: { type: "string" } } } } } };
variable.source.participants.specialist = { ...phone.source.participants.specialist, connection: { service: "telnyx", mode: "dial", number_from_variable: { section: "routing", variable: "support_phone" } } };
variable.source.participants.intake = { type: "agent", prompt: "Help the caller.", transfers: ["specialist"], variable_permissions: { routing: ["read"] } };
const overrides = structuredClone(phone);
overrides.source.defaults = { capabilities: { speech_to_text: { provider: "deepgram", model: "flux-general-multi", options: { encoding: "linear16", sample_rate: 48000 } } } };
overrides.source.participants.specialist!.capabilities = { speech_to_text: { provider: "deepgram", model: "flux-general-multi" } };
overrides.source.participants.specialist!.while_present = { record_audio: false, transcript_routes: { caller: ["specialist"] } };

const meta = {
  title: "Vxpipe/Console/Call spec editor/components/Human inspectors",
  component: HumanInspectorStory,
  parameters: { layout: "fullscreen" },
  args: { theme: "dark", initial: phone },
  argTypes: { theme: { control: "select", options: ["dark", "light"] } },
} satisfies Meta<typeof HumanInspectorStory>;
export default meta;
type Story = StoryObj<typeof meta>;
export const HumanInspectorDefault: Story = { play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await expect(canvas.findByLabelText("Participant key")).resolves.toHaveValue("specialist");
  await expect(canvas.findByLabelText("Phone number")).resolves.toHaveValue("+15550001000");
} };
export const WebDestination: Story = { args: { initial: editorFixture } };
export const VariableDestination: Story = { args: { initial: variable } };
export const VoiceAndModel: Story = { name: "Models", args: { initial: overrides, initialTab: "voice" } };
export const Presence: Story = { name: "Media", args: { initial: overrides, initialTab: "presence" } };
export const ReadOnly: Story = { args: { initial: { ...phone, readOnly: true } } };
