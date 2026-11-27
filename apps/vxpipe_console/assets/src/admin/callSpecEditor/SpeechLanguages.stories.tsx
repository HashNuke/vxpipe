import { useId, useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { EditorTheme } from "./EditorTheme";
import { Check, ChevronsUpDown, X } from "lucide-react";
import { Button } from "../components/ui/button";
import { Badge } from "../components/ui/badge";
import { Label } from "../components/ui/label";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "../components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "../components/ui/popover";
import { expect, userEvent, within } from "storybook/test";
import { CallSpecEditor } from "./flow-editor";
import { CapabilityExtraFieldContext, type CapabilityExtraFieldProps } from "./capability-fields";
import { pageSnapshot } from "./page-fixtures";
import { storyPhoneNumbers } from "./phone-number-fixtures";
import { toolCatalogFixture } from "./toolCatalogFixture";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { VoiceCatalogContext } from "../voiceCatalog";
import { storyVoiceCatalog } from "../voiceCatalogFixtures";
import { StoryNavigationContext, storyNavigation } from "../stories/storyNavigation";
import { demoTenant } from "../callSpecFixtures";
import type { CatalogCapability } from "../modelCatalog";
import type { CapabilitySelection } from "./types";
import "../admin.css";

const examples = {
  Flux: {
    provider: "deepgram",
    model: "flux",
    capability: "speech_to_text",
    label: "Expected caller languages",
    multiple: true,
    automatic: true,
    codes: ["en", "es", "fr", "de", "hi", "ru", "pt", "ja", "it", "nl"],
  },
  Transcribe: {
    provider: "google",
    model: "gemini-3.5-transcribe-live",
    capability: "speech_to_text",
    label: "Expected caller languages",
    multiple: true,
    automatic: true,
    codes: ["en-US", "en-GB", "es-US", "fr-FR"],
  },
  Flash: {
    provider: "elevenlabs",
    model: "eleven_flash_v2_5",
    capability: "text_to_speech",
    label: "Spoken language",
    multiple: false,
    automatic: true,
    codes: ["en", "es", "fr"],
  },
  Scribe: {
    provider: "elevenlabs",
    model: "scribe_v2_realtime",
    capability: "speech_to_text",
    label: "Expected caller language",
    multiple: false,
    automatic: true,
    codes: ["en", "es", "fr"],
  },
  Realtime: {
    provider: "elevenlabs",
    model: "eleven_realtime_v1_mini",
    capability: "speech_to_speech",
    label: "Conversation language",
    multiple: false,
    automatic: false,
    codes: ["en", "es", "pt-br"],
  },
  Ink: {
    provider: "cartesia",
    model: "ink-2",
    capability: "speech_to_text",
    label: "Caller language",
    multiple: false,
    automatic: true,
    codes: [],
  },
  FluxVoice: {
    provider: "deepgram",
    model: "flux",
    capability: "text_to_speech",
    label: "Spoken language",
    multiple: false,
    automatic: false,
    codes: ["en"],
  },
};
const names = new Intl.DisplayNames(["en"], { type: "language" });

type LanguageSelection = CapabilitySelection & { languages?: string[] };

function LanguageField({ kind, value, path, onChange, disabled }: CapabilityExtraFieldProps) {
  const [open, setOpen] = useState(false);
  const id = useId();
  const example = Object.values(examples).find(item => item.capability === kind && item.model === value?.model && item.provider === value.provider);
  if (!example || !value || path[0] !== "participants") return null;
  const { label, automatic, multiple, codes } = example;
  const selected = (value as LanguageSelection).languages ?? [];
  function setSelected(languages: string[]) {
    const next: LanguageSelection = { ...value! };
    if (languages.length) next.languages = languages;
    else delete next.languages;
    onChange(next);
  }
  const fixed = codes.length <= 1;
  const current = selected[0] ?? (automatic ? "" : codes[0]);
  const displayName = (code: string) => code ? names.of(code) ?? code : "Automatic";
  function choose(code: string) {
    if (!code) setSelected([]);
    else if (!multiple) setSelected([code]);
    else setSelected(selected.includes(code) ? selected.filter(item => item !== code) : [...selected, code]);
    if (!multiple || !code) setOpen(false);
  }
  return (
                <div className="space-y-2">
                  <Label htmlFor={id}>{label}</Label>
                  <Popover open={open} onOpenChange={setOpen}>
                    <PopoverTrigger asChild>
                      <Button id={id} variant="outline" role="combobox" aria-expanded={open} aria-label={label}
                        disabled={disabled || fixed} className="w-full justify-between font-normal">
                        {multiple && selected.length ? "Choose languages" : displayName(current ?? "")}
                        {!fixed && <ChevronsUpDown className="size-4 text-muted-foreground" />}
                      </Button>
                    </PopoverTrigger>
                    <PopoverContent align="start" className="w-[var(--radix-popover-trigger-width)] p-0">
                      <Command loop>
                        <CommandInput placeholder="Search languages…" aria-label="Search languages" />
                        <CommandList><CommandEmpty>No matching languages.</CommandEmpty><CommandGroup>
                          {(automatic ? ["", ...codes] : codes).map(code => {
                            const checked = multiple ? (code ? selected.includes(code) : !selected.length) : current === code;
                            return <CommandItem key={code} value={code || "Automatic"} keywords={[displayName(code)]} onSelect={() => choose(code)}>
                              <Check className={checked ? "size-4" : "invisible size-4"} />{displayName(code)}
                              {checked && <span className="sr-only">selected</span>}
                              <span className="ml-auto text-xs text-muted-foreground">{code}</span>
                            </CommandItem>;
                          })}
                        </CommandGroup></CommandList>
                      </Command>
                    </PopoverContent>
                  </Popover>
                  {multiple && <div className="flex flex-wrap gap-1.5">{selected.map(code =>
                    <Badge variant="secondary" key={code} className="gap-1 pr-0.5">{displayName(code)}
                      <Button variant="ghost" size="icon-sm" className="size-6" aria-label={`Remove ${displayName(code)}`} onClick={() => choose(code)}><X className="size-3" /></Button>
                    </Badge>)}</div>}
                  {example === examples.Realtime && <p className="text-xs text-muted-foreground">Applies to transcription and spoken replies. Defaults to English.</p>}
                </div>
  );
}

type PageProps = { example: keyof typeof examples; initial: string[] };
function LanguageExample({ example, initial }: PageProps) {
  const [{ snapshot, catalog }] = useState(() => {
    const snapshot = pageSnapshot("default");
    const catalog = structuredClone(modelCatalogFixture);
    const { provider, model, capability } = examples[example];
    const kind = capability as CatalogCapability;
    const key = kind === "speech_to_text" ? "specialist" : "intake";
    const providers = catalog[kind] ??= {};
    const models = providers[provider] ??= [];
    if (!models.some(item => item.id === model)) models.push({ id: model, name: model, default: !models.length, voices: null });
    const selection: LanguageSelection = { provider, model };
    if (initial.length) selection.languages = initial;
    if (example === "Flux") selection.options = {encoding: "linear16", sample_rate: 48000};
    if (example === "FluxVoice") selection.options = {voice:"hannah"};
    if (example === "Flash") selection.options = {voice:"JBFqnCBsd6RMkjVDRZzb"};
    if (kind === "speech_to_speech") delete snapshot.document.source.defaults;
    snapshot.document.source.participants[key]!.capabilities = { [kind]: selection };
    return { snapshot, catalog };
  });
  return <StoryNavigationContext value={storyNavigation("/editor", () => {}, demoTenant)}>
    <EditorTheme theme="dark"><VoiceCatalogContext.Provider value={storyVoiceCatalog}>
      <CapabilityExtraFieldContext.Provider value={LanguageField}>
        <CallSpecEditor snapshot={snapshot} catalog={catalog} lookups={{ phoneNumbers: storyPhoneNumbers, telephonyServices: [{ key: "office-phone", name: "Office phone", provider: "telnyx" }], credentialNames: {}, mcpIntegrations: ["calendar"], toolCatalog: toolCatalogFixture }}
          backHref="#call-specs" servicesHref="#services" onNavigate={() => {}} onReload={async () => snapshot}
          execute={async request => ({status: request.action === "publish" ? 200 : 201, revision: (request.revision ?? 0) + 1, callSpecId: "appointments"})} />
      </CapabilityExtraFieldContext.Provider>
    </VoiceCatalogContext.Provider></EditorTheme>
  </StoryNavigationContext>;
}
const meta = {
  title: "Vxpipe/Console/Call spec editor/Page/Speech languages",
  component: LanguageExample,
  play: async ({ canvasElement, args }) => {
    const body = within(canvasElement.ownerDocument.body);
    const spec = examples[args.example as keyof typeof examples];
    const participant = spec.capability === "speech_to_text" ? "specialist" : "intake";
    const node = await body.findByText(participant, {selector: "[data-flow-node-title-row] > div"});
    await userEvent.click(node);
    await userEvent.click(await body.findByRole("tab", {name: "Models"}));
    await expect(body.findByRole("combobox", {name: spec.label})).resolves.toBeVisible();
  },
  parameters: { layout: "fullscreen" },
  args: { example: "Flux", initial: [] },
} satisfies Meta<typeof LanguageExample>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Automatic: Story = {};
export const MultipleLanguages: Story = { args: { initial: ["en", "es"] } };
export const SingleLanguage: Story = { args: { example: "Scribe" } };
export const RegionalLanguages: Story = {
  args: { example: "Transcribe", initial: ["en-US", "es-US"] },
};
export const SpokenLanguage: Story = {
  args: { example: "Flash", initial: ["es"] },
};
export const ConversationLanguage: Story = { args: { example: "Realtime" } };
export const AutomaticOnly: Story = { args: { example: "Ink" } };
export const FixedVoiceLanguage: Story = { args: { example: "FluxVoice" } };
