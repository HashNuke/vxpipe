import { useEffect, useId, useState } from "react";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../components/ui/select";
import type { NamedService, PhoneNumber, PhoneNumberLoader } from "./inspectorTypes";

export function PhoneConnectionDialog({ services, currentService, currentNumber, incoming, loadNumbers, onCancel, onSelect }: {
  services: NamedService[]; currentService: string; currentNumber?: string; incoming: boolean; loadNumbers?: PhoneNumberLoader;
  onCancel: () => void; onSelect: (service: string, number?: string) => void;
}) {
  const eligible = services.filter((service) => service.provider === "twilio" || service.provider === "telnyx");
  const [service, setService] = useState(eligible.find((item) => item.key === currentService)?.key ?? eligible[0]?.key ?? "");
  const serviceId = useId();
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [page, setPage] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);
  const [numbers, setNumbers] = useState<PhoneNumber[]>([]);
  const [nextPage, setNextPage] = useState<string | null>(null);
  const [number, setNumber] = useState(currentNumber ?? "");
  const [loading, setLoading] = useState(incoming && service !== "");
  const [error, setError] = useState(false);
  useEffect(() => {
    if (!incoming || !service) return;
    const controller = new AbortController();
    setLoading(true); setError(false);
    if (page === null) setNumbers([]);
    if (!loadNumbers) { setError(true); setLoading(false); return; }
    loadNumbers(service, query, page, controller.signal).then((result) => {
      if (!controller.signal.aborted) {
        setNumbers((previous) => page === null ? result.numbers : [...previous, ...result.numbers.filter((item) => !previous.some((old) => old.id === item.id))]);
        setNextPage(result.nextPage); setLoading(false);
      }
    }).catch(() => { if (!controller.signal.aborted) { setError(true); setLoading(false); } });
    return () => controller.abort();
  }, [service, query, page, attempt, incoming, loadNumbers]);
  function chooseService(value: string) { setService(value); setPage(null); setNumber(""); setQuery(""); setSearch(""); }
  const selectable = numbers.some((item) => item.number === number && item.available);
  return <Dialog open onOpenChange={(open) => !open && onCancel()}><DialogContent className="sm:max-w-lg" onInteractOutside={(event) => { if (!eligible.length) event.preventDefault(); }} onEscapeKeyDown={(event) => { if (!eligible.length) event.preventDefault(); }}>
    <DialogHeader><DialogTitle>Phone connection</DialogTitle><DialogDescription>{incoming ? "Choose a telephony service and a phone number." : "Choose the service that will dial this person."}</DialogDescription></DialogHeader>
    <div className="flex items-center gap-3">
      <label htmlFor={serviceId} className="shrink-0 text-sm font-medium">Telephony service</label>
      <Select value={service} onValueChange={chooseService} disabled={!eligible.length}>
        <SelectTrigger id={serviceId} className="min-w-0 flex-1"><SelectValue placeholder="Not configured" /></SelectTrigger>
        <SelectContent>
          {(["twilio", "telnyx"] as const).flatMap((provider) => {
            const choices = eligible.filter((item) => item.provider === provider);
            const name = provider === "twilio" ? "Twilio" : "Telnyx";
            return choices.length ? choices.map((item) => <SelectItem key={item.key} value={item.key}>{name} · {item.name}</SelectItem>) : [<SelectItem key={provider} value={`unavailable-${provider}`} disabled>{name} · Not configured</SelectItem>];
          })}
        </SelectContent>
      </Select>
    </div>
    {!eligible.length ? <p className="text-sm text-muted-foreground">Set up at least one telephony service to use Phone connections.</p> : <>
      {incoming && <>
        <form className="flex gap-2" onSubmit={(event) => { event.preventDefault(); setQuery(search.trim()); setPage(null); setNumber(""); setAttempt((value) => value + 1); }}>
          <Input aria-label="Search phone numbers" placeholder="Search phone numbers" value={search} onChange={(event) => setSearch(event.target.value)} />
          <Button variant="outline" type="submit">Search</Button>
        </form>
        {error ? <div role="alert" className="flex items-center justify-between gap-2 text-sm"><span>Couldn’t load phone numbers.</span><Button variant="outline" size="sm" onClick={() => setAttempt((value) => value + 1)}>Retry</Button></div> : <div role="radiogroup" aria-label="Phone number" className="max-h-64 overflow-y-auto divide-y divide-border">
          {numbers.map((item) => <div key={item.id}>
            <label className={`flex items-center gap-2 px-1 py-2 text-sm ${item.available ? "cursor-pointer" : "text-muted-foreground"}`}>
              <input type="radio" name="assigned-number" checked={number === item.number} disabled={!item.available || loading} onChange={() => setNumber(item.number)} className="shrink-0 accent-primary" />
              <span className="min-w-0 flex-1 truncate font-medium" title={item.name === item.number ? item.number : `${item.name} · ${item.number}`}>{item.name === item.number ? item.number : `${item.name} · ${item.number}`}</span>
              {!item.available && <span className="shrink-0 text-xs text-muted-foreground">In use</span>}
            </label>
          </div>)}
          {!loading && !numbers.length && <p className="py-3 text-sm text-muted-foreground">{query ? "No matching phone numbers." : "Please buy a phone number on the telephony platform."}</p>}
        </div>}
        {!loading && !error && numbers.length > 0 && numbers.every((item) => !item.available) && <p className="text-sm text-muted-foreground">No phone numbers available for use. Please buy a phone number on the telephony platform</p>}
        {loading && <p role="status" className="text-sm text-muted-foreground">Loading numbers…</p>}
        {nextPage && !error && <Button variant="ghost" size="sm" disabled={loading} onClick={() => setPage(nextPage)}>Load more</Button>}
      </>}
    </>}
    <DialogFooter><Button variant="outline" onClick={onCancel}>Cancel</Button>{eligible.length > 0 && <Button disabled={!service || (incoming && (!selectable || loading || error))} onClick={() => onSelect(service, incoming ? number : undefined)}>{incoming ? "Assign number" : "Use service"}</Button>}</DialogFooter>
  </DialogContent></Dialog>;
}
