import { useId, useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, within, userEvent } from "storybook/test";
import { Check, ChevronsUpDown, Info, X } from "lucide-react";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Label } from "../components/ui/label";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "../components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "../components/ui/popover";
import { Tooltip, TooltipContent, TooltipTrigger } from "../components/ui/tooltip";
import editorStory from "./flow_editor.stories";
import { CallModelSettingsContext } from "./flow-level-inspector";

const codes = ["ar", "zh", "nl", "en", "en-GB", "en-US", "fr", "de", "hi", "it", "ja", "ko", "pt", "pt-BR", "ru", "es", "sv", "ta", "te"];
const names = new Intl.DisplayNames(["en"], { type: "language" });
const languageName = (code: string) => names.of(code) ?? code;

function ConversationLanguages({ selected, onChange }: { selected: string[]; onChange: (codes: string[]) => void }) {
  const id = useId();
  const [open, setOpen] = useState(false);
  const [hintOpen, setHintOpen] = useState(false);
  const [query, setQuery] = useState("");
  function choose(code: string) {
    onChange(code === "" ? [] : selected.includes(code) ? selected.filter(item => item !== code) : [...selected, code]);
    setQuery("");
    if (!code) setOpen(false);
  }
  return <section className="mb-5 space-y-2 border-b pb-5">
    <div className="flex items-center gap-1">
      <Label htmlFor={id}>Conversation languages</Label>
      <Tooltip open={hintOpen} onOpenChange={setHintOpen}>
        <TooltipTrigger asChild>
          <Button type="button" variant="ghost" size="icon-sm" className="size-6 text-muted-foreground"
            aria-label="How conversation languages are used"
            onClick={event => { event.preventDefault(); setHintOpen(true); }}>
            <Info className="size-3.5" aria-hidden="true" />
          </Button>
        </TooltipTrigger>
        <TooltipContent side="top" align="start" sideOffset={4} collisionPadding={12} className="max-w-64 leading-relaxed">
          Languages are listed in priority order. Models that accept multiple hints receive the full list. Models that accept one receive the first language. Fixed-language models ignore hints.
        </TooltipContent>
      </Tooltip>
    </div>
    <Popover open={open} onOpenChange={next => { setOpen(next); setQuery(""); }}>
      <div className="relative flex min-h-10 items-center rounded-md border border-control-border bg-background dark:bg-black focus-within:ring-2 focus-within:ring-ring">
        <PopoverTrigger asChild><Button id={id} role="combobox" variant="ghost" aria-expanded={open}
          aria-label="Conversation languages" className="absolute inset-0 h-full w-full justify-end pr-3 hover:bg-transparent dark:hover:bg-transparent">
          <ChevronsUpDown className="size-4 text-muted-foreground" />
        </Button></PopoverTrigger>
        <div className="pointer-events-none relative flex flex-wrap items-center gap-1.5 py-1.5 pl-2 pr-9">
          {selected.length ? selected.map((code, index) => <Badge variant="outline" key={code} className="gap-1.5 border-control-border bg-control pl-1 pr-0.5 text-foreground">
            <span className="grid size-5 place-items-center rounded-full bg-background text-xs tabular-nums text-foreground">{index + 1}</span>
            {languageName(code)}
            <Button variant="ghost" size="icon-sm" className="pointer-events-auto size-6 rounded-full" aria-label={`Remove ${languageName(code)}`} onClick={() => choose(code)}><X className="size-3" /></Button>
          </Badge>) : <span className="px-1 text-sm">Automatic</span>}
        </div>
      </div>
      <PopoverContent align="start" className="w-[var(--radix-popover-trigger-width)] p-0">
        <Command loop><CommandInput aria-label="Search languages" placeholder="Search languages…" value={query} onValueChange={setQuery} />
          <CommandList><CommandEmpty>No matching languages.</CommandEmpty><CommandGroup>
            {["", ...codes].map(code => {
              const position = selected.indexOf(code);
              const checked = code ? position >= 0 : !selected.length;
              return <CommandItem key={code} value={code || "Automatic"} keywords={code ? [languageName(code)] : []} onSelect={() => choose(code)}>
                <Check className={checked ? "size-4" : "invisible size-4"} />
                {code ? languageName(code) : "Automatic"}
                {checked && <span className="sr-only">selected</span>}
                {position >= 0 && <span className="ml-auto text-xs text-muted-foreground">#{position + 1}</span>}
              </CommandItem>;
            })}
          </CommandGroup></CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  </section>;
}

const EditorPage = editorStory.component;
function Preview({ initial }: {initial: string[]}) {
  const [selected, setSelected] = useState(initial);
  return <CallModelSettingsContext.Provider value={<ConversationLanguages selected={selected} onChange={setSelected} />}>
    <EditorPage theme="dark" scenario="default" />
  </CallModelSettingsContext.Provider>;
}

const meta = {
  title: "Vxpipe/Console/Call spec editor/Page/Conversation languages",
  component: Preview,
  parameters: {layout: "fullscreen"},
  args: {initial: ["en", "es", "fr"]},
  play: async ({canvasElement}) => {
    const page = within(canvasElement.ownerDocument.body);
    await userEvent.click(await page.findByRole("button", {name: "Call settings"}));
    await userEvent.click(await page.findByRole("tab", {name: "Models"}));
    await expect(page.findByRole("combobox", {name: "Conversation languages"})).resolves.toBeVisible();
  },
} satisfies Meta<typeof Preview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const PriorityOrder: Story = {};
export const Automatic: Story = {args: {initial: []}};
