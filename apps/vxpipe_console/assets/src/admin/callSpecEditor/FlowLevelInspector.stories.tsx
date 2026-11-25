import { emptyStoryPhoneNumbers, occupiedStoryPhoneNumbers, storyPhoneNumbers } from "./phone-number-fixtures";
import type { PhoneNumberLoader } from "./inspectorTypes";
import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { EditorTheme } from "./EditorTheme";
import { FlowLevelInspector, type CallSettingsTab } from "./flow-level-inspector";
import { editorStoryFixture as editorFixture } from "./editorFixtures";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { validateSource } from "./validation";
import type { SourceDocument } from "./types";
import "../admin.css";

const variables: SourceDocument = { ...editorFixture, source: { ...editorFixture.source,
  call_variables: { sections: { contact: { schema: { type: "object", additionalProperties: false, required: ["phone"], properties: {
    phone: { type: "string", minLength: 3 },
    preferences: { type: "array", items: { type: "object", additionalProperties: false, properties: { channel: { type: "string", enum: ["phone", "email"] }, enabled: { type: "boolean" } } } },
  } } } } },
  participants: { ...editorFixture.source.participants, intake: { type: "agent", prompt: "Collect the caller's contact details.", variable_permissions: { contact: ["read"] } },
    reviewer: { type: "agent", prompt: "Review the caller's request.", variable_permissions: { contact: ["read"] } },
  },
} };
const incoming = structuredClone(editorFixture);
incoming.source.defaults = { capabilities: { text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "hannah" } } } };
incoming.source.opening_audio = { type: "text", text: "Welcome to reception. This call may be recorded to help us improve our service." };
const outgoing = structuredClone(incoming);
delete outgoing.source.incoming_call;
outgoing.source.outgoing_call = { callee: "caller", handled_by: "intake", ring_timeout_ms: 30000 };
outgoing.source.participants.caller = { type: "human", connection: { service: "telnyx", mode: "dial" } };
outgoing.source.opening_audio = { type: "file_url", url: "https://example.test/welcome.wav" };

type Props = { theme: "dark" | "light"; initial?: SourceDocument; initialTab?: CallSettingsTab; noPhoneServices?: boolean; phoneNumbers?: PhoneNumberLoader };
function CallSettingsStory({ theme, initial = editorFixture, initialTab = "connection", noPhoneServices = false, phoneNumbers = storyPhoneNumbers }: Props) {
  const [document, onChange] = useState(initial);
  const [tab, onTabChange] = useState(initialTab);
  return <EditorTheme theme={theme}><main className="min-h-screen bg-muted p-0 sm:p-6"><div className="mx-auto h-dvh min-h-[32rem] w-full max-w-[34rem] overflow-hidden border border-border sm:h-[calc(100dvh-3rem)] sm:rounded-md">
    <FlowLevelInspector document={document} onChange={onChange} issues={validateSource(document.source)} catalog={modelCatalogFixture} lookups={{ phoneNumbers, telephonyServices: noPhoneServices ? [] : [{ key: "telnyx", name: "Telnyx", provider: "telnyx" }] }} tab={tab} onTabChange={onTabChange} />
  </div></main></EditorTheme>;
}
const meta = { title: "Vxpipe/Console/Call spec editor/components/Call settings inspector", component: CallSettingsStory, parameters: { layout: "fullscreen" }, args: { theme: "dark" }, argTypes: { theme: { control: "select", options: ["dark", "light"] } } } satisfies Meta<typeof CallSettingsStory>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Default: Story = {};
export const Variables: Story = { args: { initialTab: "variables" }, play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await userEvent.click(canvas.getByRole("button", { name: "Add section" }));
  const dialog = within(within(canvasElement.ownerDocument.body).getByRole("dialog", { name: "Add section" }));
  await userEvent.type(dialog.getByRole("textbox", { name: "Section name" }), "contact");
  await userEvent.click(dialog.getByRole("button", { name: "Add section" }));
  await expect(canvas.getByRole("heading", { name: "contact" })).toBeVisible();
} };
export const NestedVariables: Story = { args: { initial: variables, initialTab: "variables" } };
export const ReadOnlyVariables: Story = { args: { initial: { ...variables, readOnly: true, source: { ...variables.source, schema_version: "20260915.01" } }, initialTab: "variables" } };
export const Defaults: Story = { args: { initialTab: "defaults" } };
export const Media: Story = { args: { initialTab: "media" }, play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await expect(canvas.getByRole("combobox", { name: "Record audio" })).toBeVisible();
  await expect(canvas.getByRole("region", { name: "Wait sounds" })).toBeVisible();
  await expect(canvas.getByRole("combobox", { name: "Call setup" })).toBeVisible();
} };
export const Advanced: Story = { args: { initialTab: "advanced", initial: { ...editorFixture, source: { ...editorFixture.source, transfer_policy: { attempt_timeout_ms: 900 } } } } };

export const IncomingConnection: Story = { args: { initial: incoming }, play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await expect(canvas.getByRole("heading", { name: "Call settings" })).toBeVisible();
  await expect(canvas.getByRole("tab", { name: "Connection" })).toHaveAttribute("aria-selected", "true");
  await expect(canvas.findByRole("radio", { name: "Web" })).resolves.toBeChecked();
  await expect(canvas.findByRole("switch", { name: "Opening audio" })).resolves.toBeChecked();
} };
export const OutgoingConnection: Story = { args: { initial: outgoing }, play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await expect(canvas.getByText("Outgoing call")).toBeVisible();
  await expect(canvas.getByRole("tab", { name: "Connection" })).toHaveAttribute("aria-selected", "true");
  await expect(canvas.getByRole("spinbutton", { name: "Ring timeout (seconds)" })).toHaveValue(30);
  await expect(canvas.getByRole("textbox", { name: "Audio file URL" })).toHaveValue("https://example.test/welcome.wav");
} };
export const InvalidRingTimeout: Story = { args: { initial: { ...outgoing, source: { ...outgoing.source, outgoing_call: { callee: "caller", handled_by: "intake", ring_timeout_ms: 4999 } } } } };

export const ChoosePhoneNumber: Story = { args: { initial: editorFixture }, play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body);
  await userEvent.click(body.getByRole("radio", { name: "Phone" }));
  await expect(body.findByRole("dialog", { name: "Phone connection" })).resolves.toBeVisible();
  await expect(body.findByRole("radio", { name: /Support/ })).resolves.toBeDisabled();
} };
export const NoPhoneServices: Story = { args: { initial: editorFixture, noPhoneServices: true }, play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body);
  await userEvent.click(body.getByRole("radio", { name: "Phone" }));
  await expect(body.findByRole("combobox", { name: "Telephony service" })).resolves.toBeDisabled();
} };

export const NoPhoneNumbers: Story = { args: { initial: editorFixture, phoneNumbers: emptyStoryPhoneNumbers }, play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body);
  await userEvent.click(body.getByRole("radio", { name: "Phone" }));
  await expect(body.findByText("Please buy a phone number on the telephony platform.")).resolves.toBeVisible();
} };
export const AllPhoneNumbersInUse: Story = { args: { initial: editorFixture, phoneNumbers: occupiedStoryPhoneNumbers }, play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body);
  await userEvent.click(body.getByRole("radio", { name: "Phone" }));
  await expect(body.findByText("No phone numbers available for use. Please buy a phone number on the telephony platform")).resolves.toBeVisible();
} };

const fileOpening = { type: "file_url" as const, url: "https://example.test/welcome.wav" };
const speechDefaults = { capabilities: { speech_to_speech: { provider: "google", model: "gemini-live" } } };
const speechOpening: SourceDocument = { ...editorFixture, source: { ...editorFixture.source, defaults: speechDefaults, opening_audio: fileOpening } };
export const SpeechToSpeechFileOpening: Story = {
  args: { initialTab: "connection", initial: speechOpening },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByLabelText("Audio file URL")).toHaveValue(fileOpening.url);
    await userEvent.click(canvas.getByRole("combobox", { name: "Opening audio type" }));
    await expect(within(canvasElement.ownerDocument.body).getByRole("option", { name: "Spoken text" })).toHaveAttribute("aria-disabled", "true");
    await userEvent.keyboard("{Escape}");
  },
};
export const SpokenOpeningModelConflict: Story = {
  args: { initialTab: "connection", initial: { ...speechOpening, source: { ...speechOpening.source, opening_audio: { type: "text", text: "Welcome to reception." } } } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByLabelText("Opening message")).toHaveValue("Welcome to reception.");
    await expect(canvas.getByRole("button", { name: "Call settings → Models" })).toBeVisible();
  },
};
export const OpeningWithoutDefaultVoice: Story = {
  args: { initialTab: "connection", initial: { ...editorFixture, source: { ...editorFixture.source, opening_audio: fileOpening } } },
};
