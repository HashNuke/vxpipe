import { useId, useState } from "react";
import { Check, ChevronsUpDown, Info, X } from "lucide-react";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Label } from "../components/ui/label";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "../components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "../components/ui/popover";
import { TooltipProvider, Tooltip, TooltipContent, TooltipTrigger } from "../components/ui/tooltip";

import { conversationLanguageCodes } from "./conversation-language-codes";
import { IssueAnchor } from "./issue-anchor";
import { editSource } from "./editSource";
import type { InspectorProps } from "./inspectorTypes";
import { defaultFilter } from "cmdk";

const names = new Intl.DisplayNames(["en"], { type: "language" });

// Intl.DisplayNames collapses several supported tags to the same English name
// (tl/fil and cmn-CN/zh-CN). Keep the shared JSON codes unchanged and disambiguate
// in the UI so language vs macrolanguage choices stay explicit.
const displayOverrides: Record<string, string> = {
  tl: "Tagalog",
  "tl-PH": "Tagalog (Philippines)",
  fil: "Filipino",
  "fil-PH": "Filipino (Philippines)",
  cmn: "Mandarin",
  "cmn-CN": "Mandarin (China)",
  "cmn-Hans-CN": "Mandarin (Simplified, China)",
  "cmn-TW": "Mandarin (Taiwan)",
};

export const conversationLanguageName = (code: string) => displayOverrides[code] ?? names.of(code) ?? code;

const codes = [...conversationLanguageCodes].sort((a, b) =>
  conversationLanguageName(a).localeCompare(conversationLanguageName(b), "en") || a.localeCompare(b),
);

// Exact code matches must outrank fuzzy name matches (e.g. typing "es" must
// select Spanish, not Estonian). cmdk scores `value + keywords` with fuzzy
// matching, so keep the code as the value and the display name as the keyword,
// then boost exact code hits above any fuzzy score (which tops out at 1).
function languageFilter(value: string, search: string, keywords?: string[]): number {
  const query = search.trim().toLowerCase();
  if (!query) return 1;
  if (value.toLowerCase() === query) return 2;
  return defaultFilter(value, search, keywords);
}

export function ConversationLanguages({ document, onChange, issues }: InspectorProps) {
  const saved = document.source.conversation_languages;
  const selected = Array.isArray(saved) ? saved.filter(code => conversationLanguageCodes.includes(code)) : [];
  const id = useId();
  const [open, setOpen] = useState(false);
  const [hintOpen, setHintOpen] = useState(false);
  const [query, setQuery] = useState("");
  function choose(code: string) {
    const next = code === "" ? [] : selected.includes(code) ? selected.filter(item => item !== code) : [...selected, code];
    onChange(editSource(document, source => { source.conversation_languages = next; }));
    setQuery("");
    if (!code) setOpen(false);
  }
  return <IssueAnchor path={["conversation_languages"]} issues={issues} className="mb-5 space-y-2 border-b pb-5">
    <div className="flex items-center gap-1">
      <Label htmlFor={id}>Conversation languages</Label>
      <TooltipProvider><Tooltip open={hintOpen} onOpenChange={setHintOpen}>
        <TooltipTrigger asChild>
          <Button type="button" variant="ghost" size="icon-sm" className="size-6 text-muted-foreground"
            aria-label="How conversation languages are used"
            onClick={event => { event.preventDefault(); setHintOpen(true); }}>
            <Info className="size-3.5" aria-hidden="true" />
          </Button>
        </TooltipTrigger>
        <TooltipContent side="top" align="start" sideOffset={4} collisionPadding={12} className="max-w-64 leading-relaxed">
          Languages are listed in priority order. Models that accept multiple hints receive the supported languages in order. Models that accept one receive the first language they support. Fixed-language models ignore hints.
        </TooltipContent>
      </Tooltip></TooltipProvider>
    </div>
    <Popover open={open} onOpenChange={next => { setOpen(next); setQuery(""); }}>
      <div className="relative flex min-h-10 items-center rounded-md border border-control-border bg-background dark:bg-black focus-within:ring-2 focus-within:ring-ring">
        <PopoverTrigger asChild><Button disabled={document.readOnly} id={id} role="combobox" variant="ghost" aria-expanded={open}
          aria-label="Conversation languages" className="absolute inset-0 h-full w-full justify-end pr-3 hover:bg-transparent dark:hover:bg-transparent">
          <ChevronsUpDown className="size-4 text-muted-foreground" />
        </Button></PopoverTrigger>
        <div className="pointer-events-none relative flex min-w-0 flex-1 flex-wrap items-center gap-1.5 py-1.5 pl-2 pr-9">
          {selected.length ? selected.map((code, index) => <Badge variant="outline" key={code} className="max-w-full gap-1.5 border-control-border bg-control pl-1 pr-0.5 text-foreground">
            <span className="grid size-5 shrink-0 place-items-center rounded-full bg-background text-xs tabular-nums text-foreground">{index + 1}</span>
            <span className="min-w-0 truncate" title={conversationLanguageName(code)}>{conversationLanguageName(code)}</span>
            <span className="shrink-0 text-xs text-muted-foreground">{code}</span>
            <Button disabled={document.readOnly} variant="ghost" size="icon-sm" className="pointer-events-auto size-6 rounded-full" aria-label={`Remove ${conversationLanguageName(code)} (${code})`} onClick={() => choose(code)}><X className="size-3" /></Button>
          </Badge>) : <span className="px-1 text-sm">Automatic</span>}
        </div>
      </div>
      <PopoverContent align="start" className="w-[var(--radix-popover-trigger-width)] p-0">
        <Command loop label="Search languages" filter={languageFilter}><CommandInput aria-label="Search languages" placeholder="Search languages…" value={query} onValueChange={setQuery} />
          <CommandList><CommandEmpty>No matching languages.</CommandEmpty><CommandGroup>
            {["", ...codes].map(code => {
              const position = selected.indexOf(code);
              const checked = code ? position >= 0 : !selected.length;
              const name = code ? conversationLanguageName(code) : "Automatic";
              return <CommandItem key={code || "automatic"} value={code || "automatic"} keywords={code ? [name] : ["Automatic"]} onSelect={() => choose(code)}>
                <Check className={checked ? "size-4" : "invisible size-4"} />
                {code ? <><span>{name}</span><span className="ml-auto text-xs text-muted-foreground">{code}</span></> : "Automatic"}
                {checked && <span className="sr-only">selected</span>}
                {position >= 0 && <span className="text-xs tabular-nums text-muted-foreground">#{position + 1}</span>}
              </CommandItem>;
            })}
          </CommandGroup></CommandList>
        </Command>
      </PopoverContent>
    </Popover>
  </IssueAnchor>;
}
