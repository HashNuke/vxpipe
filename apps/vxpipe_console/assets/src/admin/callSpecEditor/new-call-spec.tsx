import { useId, useState } from "react";
import { PhoneIncoming, PhoneOutgoing } from "lucide-react";
import { Button } from "../components/ui/button";
import { Label } from "../components/ui/label";
import { RadioGroup, RadioGroupItem } from "../components/ui/radio-group";
import type { ModelCatalog } from "../modelCatalog";
import { ChoiceField } from "./editor-fields";
import type { NamedService } from "./inspectorTypes";
import { newCallSpec } from "./seed";
import type { SourceDocument } from "./types";

export function NewCallSpec({ catalog, services, servicesHref, onCreate, onCancel }: {
  catalog: ModelCatalog;
  services: NamedService[];
  servicesHref: string;
  onCreate: (document: SourceDocument) => void;
  onCancel: () => void;
}) {
  const id = useId();
  const [direction, setDirection] = useState("");
  const [service, setService] = useState("");
  const [error, setError] = useState<string>();
  const phoneServices = services.filter((item) => item.key !== "web");
  const ready = direction === "incoming" || (direction === "outgoing" && phoneServices.some((item) => item.key === service));
  return <main className="min-h-dvh bg-background px-6 py-12 sm:py-20">
    <form className="mx-auto max-w-md space-y-6" onSubmit={(event) => {
      event.preventDefault();
      if (!ready) return;
      try { onCreate(newCallSpec(catalog, direction === "outgoing" ? { direction, service } : { direction: "incoming" })); }
      catch (error) { setError(error instanceof Error ? error.message : "Couldn't create the call spec. Try again."); }
    }}>
      <div className="space-y-2"><h1 className="text-xl font-semibold">New call spec</h1>
        <p className="text-sm text-muted-foreground">Choose the call direction. It cannot be changed after creation.</p></div>
      <RadioGroup aria-label="Call direction" value={direction} onValueChange={(value) => { setDirection(value); setError(undefined); }} className="gap-0 divide-y rounded-md border">
        {([
          ["incoming", "Incoming call", "Accept calls over web or phone.", PhoneIncoming],
          ["outgoing", "Outgoing call", "Call someone through a phone service.", PhoneOutgoing],
        ] as const).map(([value, title, description, Icon]) => <Label key={value} htmlFor={`${id}-${value}`} className="flex cursor-pointer items-center gap-3 p-4">
          <RadioGroupItem id={`${id}-${value}`} value={value} aria-label={title} />
          <Icon className="size-4 shrink-0 text-muted-foreground" />
          <span className="space-y-1"><span className="block text-sm font-medium">{title}</span><span className="block text-sm font-normal text-muted-foreground">{description}</span></span>
        </Label>)}
      </RadioGroup>
      {direction === "outgoing" && (phoneServices.length ? <ChoiceField label="Phone service" path={["service"]} value={service}
        choices={[{ value: "", label: "Choose a phone service" }, ...phoneServices.map((item) => ({ value: item.key, label: item.name }))]} onChange={setService} />
        : <p className="text-sm text-muted-foreground">Outgoing calls need a phone service. <a className="text-foreground underline underline-offset-4" href={servicesHref}>Configure a phone service</a> to continue.</p>)}
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <div className="flex justify-end gap-2"><Button type="button" variant="outline" onClick={onCancel}>Cancel</Button><Button type="submit" disabled={!ready}>Create call spec</Button></div>
    </form>
  </main>;
}
