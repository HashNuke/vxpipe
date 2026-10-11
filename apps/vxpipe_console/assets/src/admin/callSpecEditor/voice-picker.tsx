import { useEffect, useId, useState } from "react";
import { Search, SlidersHorizontal } from "lucide-react";
import { Button } from "../components/ui/button";
import { Badge } from "../components/ui/badge";
import { Input } from "../components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { RadioGroup, RadioGroupItem } from "../components/ui/radio-group";
import type { Voice, VoiceCatalogClient, VoiceCatalogDescriptor, VoiceCatalogPage, VoiceCatalogQuery, VoiceScope } from "../voiceCatalog";
import { VoiceFilterControl } from "./voice-filters";

type Props = { client: VoiceCatalogClient; scope: VoiceScope; current?: Voice; onSelect: (voice: Voice) => void; onClose: () => void; onReturnFocus: () => void };
export function VoicePicker({ client, scope, current, onSelect, onClose, onReturnFocus }: Props) {
  const id = useId();
  const [descriptor, setDescriptor] = useState<VoiceCatalogDescriptor>();
  const [query, setQuery] = useState<VoiceCatalogQuery>({ search: "", filters: {}, cursor: null });
  const [draft, setDraft] = useState({ search: "", filters: {} } as Pick<VoiceCatalogQuery, "search" | "filters">);
  const [applied, setApplied] = useState(false);
  const [result, setResult] = useState<{ query: VoiceCatalogQuery; page: VoiceCatalogPage }>();
  const [error, setError] = useState(false);
  const [retry, setRetry] = useState(0);
  const [selected, setSelected] = useState(current);
  const [showFilters, setShowFilters] = useState(false);
  useEffect(() => {
    const controller = new AbortController();
    Promise.all([client.describe(scope, controller.signal), client.list(scope, query, controller.signal)]).then(([description, page]) => {
      if (controller.signal.aborted) return;
      setDescriptor(description); setError(false);
      setResult(previous => ({ query, page: query.cursor && previous ? { ...page, voices: [...new Map([...previous.page.voices, ...page.voices].map(voice => [voice.id, voice])).values()] } : page }));
    }).catch(() => { if (!controller.signal.aborted) setError(true); });
    return () => controller.abort();
  }, [client, scope, query, retry]);
  const loading = !error && result?.query !== query;
  const page = result?.page;
  const changeQuery = (next: VoiceCatalogQuery) => { setError(false); setQuery(next); };
  const count = Object.keys(draft.filters).length;
  const dirty = draft.search !== query.search || JSON.stringify(draft.filters) !== JSON.stringify(query.filters);
  const status = dirty ? "Unapplied changes" : loading ? (result ? "Updating voices…" : "Loading voices…") : error ? "Couldn’t update results" : applied ? "Results updated" : "";
  return <Dialog open onOpenChange={open => { if (!open) onClose(); }}>
    <DialogContent onCloseAutoFocus={event => { event.preventDefault(); onReturnFocus(); }} className="flex h-[min(42rem,calc(100dvh-2rem))] max-h-[calc(100dvh-2rem)] flex-col gap-0 overflow-hidden p-0 sm:max-w-3xl">
      <DialogHeader className="shrink-0 flex-row flex-wrap items-baseline gap-x-4 gap-y-1 py-4 pr-12 pl-5 text-left sm:pl-6">
        <DialogTitle>Choose a voice</DialogTitle>
        <DialogDescription>{descriptor ? `${descriptor.providerName} · ${descriptor.modelName}` : "Loading voice catalog…"}</DialogDescription>
      </DialogHeader>
      <div className="min-h-0 flex-1 overflow-y-auto">
        <form onSubmit={event => { event.preventDefault(); if (dirty) { setApplied(true); changeQuery({ ...draft, cursor: null }); } }} className="flex flex-col gap-3 border-y bg-muted/30 px-5 py-3 sm:px-6">
          <div className="flex flex-wrap gap-2">
            {descriptor?.search !== false && <div className="relative min-w-0 flex-1 basis-full sm:basis-0"><Search aria-hidden="true" className="absolute top-2 left-3 size-4 text-muted-foreground" />
              <Input aria-label="Search voices" type="search" className="h-8 pl-9 text-xs md:text-xs" placeholder="Search voices" value={draft.search} onChange={event => setDraft({ ...draft, search: event.target.value })} /></div>}
            {!!descriptor?.filters.length && <Button type="button" size="sm" className="text-xs" variant="outline" aria-expanded={showFilters} aria-controls={`${id}-filters`} onClick={() => setShowFilters(!showFilters)}>
              <SlidersHorizontal className="size-4" />Filters{count ? ` (${count})` : ""}</Button>}
            <Button type="submit" size="sm" className="text-xs" variant="outline" disabled={!dirty}>Apply filters</Button>
          </div>
          {showFilters && <div id={`${id}-filters`} className="grid grid-cols-1 gap-4 pt-1 sm:grid-cols-3">{descriptor?.filters.map(filter => <VoiceFilterControl key={filter.key} filter={filter} value={draft.filters[filter.key]}
            onChange={value => { const filters = { ...draft.filters }; if (value === undefined) delete filters[filter.key]; else filters[filter.key] = value; setDraft({ ...draft, filters }); }} />)}</div>}
          <div className={status || count || draft.search ? "flex min-h-5 flex-wrap items-center gap-x-4 gap-y-1" : "sr-only"}>
            <span role="status" className="text-xs text-muted-foreground">{status}</span>
            {(count > 0 || draft.search) && <Button type="button" variant="link" className="ml-auto h-auto p-0 text-xs" onClick={() => setDraft({ search: "", filters: {} })}>Clear filters and search</Button>}
          </div>
        </form>
        <div aria-busy={loading} className="min-h-56">
          {error ? <div role="alert" className="space-y-3 px-5 py-6 sm:px-6"><p className="font-medium">Couldn’t load voices</p><p className="text-sm text-muted-foreground">Your saved voice hasn’t changed. Try loading the catalog again.</p>
            <Button variant="outline" onClick={() => { setError(false); setResult(undefined); setQuery({ ...query, cursor: null }); setRetry(retry + 1); }}>Retry</Button></div>
          : loading && !query.cursor ? <p className="px-5 py-10 text-sm text-muted-foreground sm:px-6">Loading voices…</p>
          : <>
            {page?.voices.length ? <RadioGroup aria-label="Voices" value={selected?.id ?? ""} className="gap-0 divide-y" onValueChange={value => setSelected(page.voices.find(voice => voice.id === value))}>
              {page.voices.map((voice, index) => <label key={voice.id} htmlFor={`${id}-${index}`} className={`flex min-w-0 cursor-pointer items-start gap-3 px-5 py-2.5 transition-colors sm:px-6 ${selected?.id === voice.id ? "bg-primary/10" : "hover:bg-muted/60"}`}>
                <RadioGroupItem id={`${id}-${index}`} value={voice.id} className="mt-1" aria-label={`${voice.name}${voice.id !== voice.name ? ` · ${voice.id}` : ""}`} aria-describedby={`${id}-${index}-details`} />
                <span id={`${id}-${index}-details`} className="min-w-0 flex-1 space-y-1">
                  <span className="flex flex-wrap items-center gap-x-3 gap-y-1"><span className="font-medium wrap-anywhere">{voice.name}</span>
                    {!!voice.attributes.length && <span className="flex flex-wrap gap-1">{voice.attributes.map(attribute => <Badge variant="secondary" className="rounded-sm px-1.5 py-0 font-normal" key={attribute.key} title={attribute.label}>{attribute.value}</Badge>)}</span>}
                    {current?.id === voice.id && <span className="ml-auto shrink-0 text-xs text-muted-foreground">Current</span>}</span>
                  {voice.description && <span className="block text-sm text-muted-foreground">{voice.description}</span>}
                  {voice.id !== voice.name && <span className="block break-all text-xs text-muted-foreground/85 dark:text-muted-foreground/70">ID: {voice.id}</span>}
                </span>
              </label>)}
            </RadioGroup> : <div className="space-y-2 px-5 py-8 sm:px-6"><p className="font-medium">No voices found</p><p className="text-sm text-muted-foreground">Try a different search or clear your filters.</p></div>}
            {page?.nextCursor && <div className="px-5 py-3 sm:px-6"><Button variant="outline" className="w-full" disabled={loading || dirty} onClick={() => changeQuery({ ...query, cursor: page.nextCursor })}>{loading ? "Loading voices…" : "Load more voices"}</Button></div>}
          </>}
        </div>
      </div>
      <div className="flex shrink-0 flex-wrap items-center justify-between gap-3 border-t bg-background px-5 py-4 sm:px-6">
        <p className="min-w-0 text-sm"><span className="text-muted-foreground">Selected: </span><span className="font-medium wrap-anywhere">{selected?.name ?? "None"}</span></p>
        <div className="ml-auto flex gap-2"><Button variant="outline" onClick={onClose}>Cancel</Button><Button disabled={!selected || selected.id === current?.id} onClick={() => { if (selected) onSelect(selected); }}>Use voice</Button></div>
      </div>
    </DialogContent>
  </Dialog>;
}
