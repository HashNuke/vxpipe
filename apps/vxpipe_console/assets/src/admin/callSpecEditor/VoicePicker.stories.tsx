import { useMemo, useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { EditorTheme } from "./EditorTheme";
import { VoiceField } from "./voice-field";
import { fixtureVoiceCatalog } from "../voiceCatalogFixtures";
import "../admin.css";

type Props = { provider: string; model: string; voice: string; theme: "dark" | "light"; fail?: boolean; loading?: boolean };
function VoicePickerStory({ provider, model, voice, theme, fail, loading }: Props) {
  const [value, onChange] = useState(voice);
  const client = useMemo(() => fixtureVoiceCatalog({ fail, loading }), [fail, loading]);
  return <EditorTheme theme={theme}><main className="min-h-dvh bg-background p-6 text-foreground sm:p-10">
    <div className="mx-auto max-w-md space-y-6">
      <div className="space-y-2"><h1 className="text-lg font-semibold">{provider === "openai" ? "Speech to speech" : "Text to speech"}</h1><p className="text-sm text-muted-foreground">{provider} · {model}</p></div>
      <VoiceField key={`${provider}/${model}`} client={client} provider={provider} model={model} capability={provider === "openai" ? "speech_to_speech" : "text_to_speech"}
        value={value} onChange={onChange} path={["options", provider === "rime" ? "speaker" : "voice"]} />
      <p className="text-xs text-muted-foreground">UI preview with sample catalog data.</p>
    </div>
  </main></EditorTheme>;
}
const meta = {
  title: "Vxpipe/Console/Call spec editor/components/Voice picker", component: VoicePickerStory, parameters: { layout: "fullscreen" },
  args: { provider: "cartesia", model: "sonic-3.6", voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4", theme: "dark" },
} satisfies Meta<typeof VoicePickerStory>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Cartesia: Story = {};
export const ElevenLabs: Story = { args: { provider: "elevenlabs", model: "eleven_flash_v2_5", voice: "JBFqnCBsd6RMkjVDRZzb" } };
export const Google: Story = { args: { provider: "google", model: "gemini-3.1-flash-tts-preview", voice: "Kore" } };
export const NamesOnly: Story = { args: { provider: "openai", model: "gpt-live-1", voice: "marin" } };
export const Deepgram: Story = { args: { provider: "deepgram", model: "flux", voice: "hannah" } };
export const Rime: Story = { args: { provider: "rime", model: "coda", voice: "astra" } };
export const UnavailableSavedVoice: Story = { args: { voice: "saved-private-voice" } };
export const CatalogError: Story = { args: { fail: true } };
export const Loading: Story = { args: { loading: true } };
export const Light: Story = { args: { theme: "light" } };
