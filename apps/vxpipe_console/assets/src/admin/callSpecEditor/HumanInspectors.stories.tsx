import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, within } from "storybook/test";
import { EditorTheme } from "./EditorTheme";
import { HumanInspector } from "./human-inspector";
import { InboundInspector } from "./inbound-inspector";
import type { HumanInspectorTab } from "./human-inspector-tabs";
import { editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import type { SourceDocument } from "./types";
import { validateSource } from "./validation";
import "../admin.css";

type Props = { entry: boolean; theme: "light" | "dark"; initial: SourceDocument; initialTab?: HumanInspectorTab };
function HumanInspectorStory({ entry, theme, initial, initialTab = "connection" }: Props) {
  const [document, onChange] = useState(initial);
  const [participantKey, onRenamed] = useState("specialist");
  const [tab, onTabChange] = useState(initialTab);
  const props = { document, onChange, issues: validateSource(document.source), catalog: modelCatalogFixture, lookups: { telephonyServices: [{ key: "phone", name: "Reception phone" }], credentialNames: { deepgram: ["production"] }, mcpIntegrations: [] }, tab, onTabChange };
  return <EditorTheme theme={theme}><main className="min-h-screen bg-muted p-0 sm:p-6"><div className="mx-auto h-dvh min-h-[32rem] w-full max-w-[34rem] overflow-hidden border border-border bg-background sm:h-[calc(100dvh-3rem)] sm:rounded-md">
    {entry ? <InboundInspector {...props} /> : Object.hasOwn(document.source.participants, participantKey) ? <HumanInspector {...props} participantKey={participantKey} onRenamed={onRenamed} /> : <p className="p-4 text-sm text-muted-foreground">Participant removed.</p>}
  </div></main></EditorTheme>;
}
const phone = structuredClone(editorFixture);
phone.source.participants.specialist = { type: "human", description: "Appointment specialist", connection: { service: "phone", mode: "dial", admission: "transfer", number: "+15550001000" }, transfer_notice: "Please help this caller with their appointment." };
const incoming = structuredClone(editorFixture);
incoming.source.opening_audio = { type: "text", text: "Welcome to reception. This call may be recorded to help us improve our service.", text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "hannah" } } };
const outgoing = structuredClone(incoming);
delete outgoing.source.incoming_call;
outgoing.source.outgoing_call = { callee: "caller", handled_by: "intake", ring_timeout_ms: 30000 };
outgoing.source.participants.caller = { type: "human", connection: { service: "phone", mode: "dial" } };
outgoing.source.opening_audio = { type: "file_url", url: "https://example.test/welcome.wav" };
const variable = structuredClone(phone);
variable.source.call_variables = { sections: { routing: { schema: { type: "object", properties: { support_phone: { type: "string" } } } } } };
variable.source.participants.specialist = { ...phone.source.participants.specialist, connection: { service: "phone", mode: "dial", number_from_variable: { section: "routing", variable: "support_phone" } } };
variable.source.participants.intake = { type: "agent", prompt: "Help the caller.", transfers: ["specialist"], variable_permissions: { routing: ["read"] } };
const overrides = structuredClone(phone);
overrides.source.defaults = { capabilities: { text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "hannah" } } } };
overrides.source.participants.specialist!.capabilities = { speech_to_text: { provider: "deepgram", model: "flux-general-multi" } };
overrides.source.participants.specialist!.while_present = { record_audio: false, transcript_routes: { caller: ["specialist"] } };

const meta = {
  title: "Vxpipe/Console/Call spec editor/Human inspectors",
  component: HumanInspectorStory,
  parameters: { layout: "fullscreen" },
  args: { entry: false, theme: "dark", initial: phone },
  argTypes: { theme: { control: "select", options: ["dark", "light"] } },
} satisfies Meta<typeof HumanInspectorStory>;
export default meta;
type Story = StoryObj<typeof meta>;
// Adapted from the committed Callpipe HumanInspectorDefault and InboundInspectorDefault stories.
export const HumanInspectorDefault: Story = { play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await expect(canvas.findByLabelText("Participant key")).resolves.toHaveValue("specialist");
  await expect(canvas.findByLabelText("Phone number")).resolves.toHaveValue("+15550001000");
} };
export const InboundInspectorDefault: Story = { args: { entry: true, initial: incoming }, play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await expect(canvas.findByRole("combobox", { name: "Connection service" })).resolves.toHaveTextContent("Web");
  await expect(canvas.findByRole("switch", { name: "Opening audio" })).resolves.toBeChecked();
} };
export const OutgoingEntry: Story = { args: { entry: true, initial: outgoing } };
export const WebDestination: Story = { args: { initial: editorFixture } };
export const VariableDestination: Story = { args: { initial: variable } };
export const VoiceAndModel: Story = { args: { initial: overrides, initialTab: "voice" } };
export const Presence: Story = { args: { initial: overrides, initialTab: "presence" } };
export const ReadOnly: Story = { args: { initial: { ...phone, readOnly: true } } };
export const InvalidRingTimeout: Story = { args: { entry: true, initial: { ...outgoing, source: { ...outgoing.source, outgoing_call: { callee: "caller", handled_by: "intake", ring_timeout_ms: 4999 } } } } };
