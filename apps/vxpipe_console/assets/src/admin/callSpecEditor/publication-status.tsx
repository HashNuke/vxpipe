import { useState } from "react";
import { History } from "lucide-react";
import { Badge } from "../components/ui/badge";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "../components/ui/dialog";
import { publicationChangeClasses, publicationLabel, publicationLiveClasses, type CallSpecPublication } from "../callSpecPublication";

const formatDate = (date: string) => new Intl.DateTimeFormat("en-GB", {
  day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "UTC", timeZoneName: "short",
}).format(new Date(date));

export function PublicationStatus({ publication }: { publication: CallSpecPublication }) {
  const [open, setOpen] = useState(false);
  const label = publicationLabel(publication.version, publication.unpublishedChanges);
  const history = publication.history.slice(0, 3);
  if (publication.version === null) return <Badge variant="secondary" className="min-h-7 px-2.5">Draft</Badge>;
  return <Dialog open={open} onOpenChange={setOpen}>
    <DialogTrigger asChild><Badge asChild variant="outline" className={`min-h-7 gap-1.5 px-2.5 hover:brightness-110 focus-visible:outline-none ${publication.unpublishedChanges ? publicationChangeClasses : "hover:bg-muted"}`}>
      <button type="button" aria-haspopup="dialog"><History aria-hidden="true" /><span>{label}</span></button>
    </Badge></DialogTrigger>
      <DialogContent className="max-h-[85dvh] overflow-y-auto sm:max-w-lg">
        <DialogHeader><DialogTitle>Version history</DialogTitle><DialogDescription>Showing {history.length} recent published {history.length === 1 ? "version" : "versions"}</DialogDescription></DialogHeader>
        <div className="divide-y divide-border">
          {publication.unpublishedChanges && publication.draftSavedAt && <div className="py-4">
            <h3 className="text-sm font-medium">Unpublished changes</h3>
            <time dateTime={publication.draftSavedAt} className="mt-1 block text-xs text-muted-foreground">{formatDate(publication.draftSavedAt)}</time>
          </div>}
          {history.map(event => <div key={event.version} className="py-4">
            <div className="flex items-center gap-2"><h3 className="text-sm font-medium">Version {event.version}</h3>
              {event.version === publication.version && <Badge className={publicationLiveClasses}>Live</Badge>}
            </div>
            <time dateTime={event.publishedAt} className="mt-1 block text-xs text-muted-foreground">{formatDate(event.publishedAt)}</time>
          </div>)}
        </div>
      </DialogContent>
  </Dialog>;
}
