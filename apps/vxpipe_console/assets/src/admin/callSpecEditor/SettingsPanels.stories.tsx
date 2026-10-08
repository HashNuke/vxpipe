import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, waitFor, within } from "storybook/test";
import { EditorTheme } from "./EditorTheme";
import { InspectorShell } from "./inspector-primitives";
import { DirectionPanel } from "./direction-panel";
import { MediaPolicyFields } from "./media-policy-fields";
import { WaitSoundsPanel } from "./wait-sounds-panel";
import { AdvancedPanel } from "./advanced-panel";
import { DefaultsPanel } from "./defaults-panel";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import type { ModelCatalog } from "../modelCatalog";
import { editorFixture } from "./editorFixtures";
import { validateSource } from "./validation";
import type { SourceDocument } from "./types";
import "../admin.css";

type Props = { panel: "direction" | "media" | "wait" | "advanced" | "defaults"; theme: "light" | "dark"; initial?: SourceDocument; catalog?: ModelCatalog };
const titles = { direction: "Direction", media: "Media and recording", wait: "Wait sounds", advanced: "Advanced", defaults: "Default capabilities" };
function SettingsPanelStory({ panel, theme, initial = editorFixture, catalog = modelCatalogFixture }: Props) {
  const [document, onChange] = useState(initial);
  const props = { document, onChange, issues: validateSource(document.source) };
  return <EditorTheme theme={theme}><main className="min-h-screen bg-muted p-0 sm:p-6"><div className="mx-auto h-dvh min-h-[32rem] w-full sm:h-[calc(100dvh-3rem)] max-w-[34rem] overflow-hidden border border-border bg-background sm:rounded-md">
    <InspectorShell title="Call settings" subtitle={titles[panel]}>
      {panel === "direction" ? <DirectionPanel {...props} services={[{ key: "phone", name: "Reception phone" }]} />
        : panel === "defaults" ? <DefaultsPanel {...props} catalog={catalog} credentialNames={{ deepgram: ["production"], cartesia: ["speech"] }} />
        : panel === "media" ? <MediaPolicyFields {...props} participantKey={null} />
        : panel === "wait" ? <WaitSoundsPanel {...props} /> : <AdvancedPanel {...props} />}
    </InspectorShell>
  </div></main></EditorTheme>;
}
const meta = {
  title: "Vxpipe/Console/Call spec editor/Call settings panels",
  component: SettingsPanelStory,
  parameters: { layout: "fullscreen" },
  args: { theme: "dark", panel: "direction" },
  argTypes: { theme: { control: "select", options: ["dark", "light"] } },
} satisfies Meta<typeof SettingsPanelStory>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Direction: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Switch to outgoing" }));
    const body = within(canvasElement.ownerDocument.body);
    await expect(body.getByRole("button", { name: "Use outgoing direction" })).toBeDisabled();
    await userEvent.click(body.getByRole("button", { name: "Cancel" }));
    await waitFor(() => expect(body.queryByRole("dialog")).not.toBeInTheDocument());
    canvasElement.dataset.editorStoryReady = "true";
  },
};
export const MediaAndRecording: Story = { args: { panel: "media", initial: { ...editorFixture, source: { ...editorFixture.source, media_policy: { audio_routes: { intake: ["caller"], caller: ["intake"] }, record_audio: false } } } } };
export const WaitSounds: Story = { args: { panel: "wait", initial: { ...editorFixture, source: { ...editorFixture.source, wait_sounds: { transfer_to_agent: "https://example.test/wait.wav", transfer_joining: null } } } } };
export const AllSilent: Story = { args: { panel: "wait", initial: { ...editorFixture, source: { ...editorFixture.source, wait_sounds: null } } } };
export const Advanced: Story = { args: { panel: "advanced", initial: { ...editorFixture, source: { ...editorFixture.source, transfer_policy: { attempt_timeout_ms: 900 } } } } };
export const HistoricalReadOnly: Story = { args: { panel: "advanced", initial: { ...editorFixture, readOnly: true, source: { ...editorFixture.source, schema_version: "20260915.01" } } } };
export const DefaultModels: Story = { args: { panel: "defaults" } };
export const SavedVoice: Story = { args: { panel: "defaults", initial: { ...editorFixture, source: { ...editorFixture.source, defaults: { capabilities: { text_to_speech: { provider: "deepgram", model: "flux", options: { voice: "haley" } } } } } } } };
export const LegacyModel: Story = { args: { panel: "defaults", initial: { ...editorFixture, source: { ...editorFixture.source, defaults: { capabilities: { text_to_speech: { provider: "deepgram", model: "flux-haley-en", options: { encoding: "linear16", sample_rate: 48000 } } } } } } } };
// Synthetic descriptor exercises the declared list contract; it is not a runtime provider.
export const KnownVoicesFixture: Story = { args: {
  panel: "defaults",
  catalog: { text_to_speech: { fixture: [{ id: "listed-voices", name: "Story fixture", default: true, voices: { type: "list", parameter: "speaker", values: [{ id: "a", name: "Alpha", default: true }, { id: "b", name: "Beta", default: false }] } }] } },
  initial: { ...editorFixture, source: { ...editorFixture.source, defaults: { capabilities: { text_to_speech: { provider: "fixture", model: "listed-voices", options: { speaker: "a" } } } } } },
} };
