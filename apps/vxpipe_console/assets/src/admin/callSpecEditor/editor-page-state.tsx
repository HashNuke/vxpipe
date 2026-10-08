import { ArrowLeft, RotateCcw } from "lucide-react";
import { Button } from "../components/ui/button";
import { Skeleton } from "../components/ui/skeleton";

export function EditorPageState({ status, resource = "spec", backHref, onRetry }: { status: "loading" | "error"; resource?: "spec" | "catalog"; backHref: string; onRetry: () => void }) {
  return <main className="flex min-h-dvh flex-col bg-muted p-4 sm:p-6" aria-busy={status === "loading"}>
    <div><Button asChild variant="outline" size="sm"><a href={backHref}><ArrowLeft className="h-4 w-4" />Back to call specs</a></Button></div>
    {status === "loading" ? <div className="m-auto w-full max-w-lg space-y-4 p-6">
      <h1 className="sr-only">Call spec editor</h1><p role="status" className="text-sm text-muted-foreground">Loading call spec editor…</p>
      <div aria-hidden="true" className="space-y-3"><Skeleton className="h-8 w-2/3" /><Skeleton className="h-40 w-full" /><Skeleton className="h-8 w-1/2" /></div>
    </div> : <section className="m-auto w-full max-w-lg space-y-4 rounded-md border bg-background p-6">
      <h1 className="text-lg font-semibold">{resource === "catalog" ? "Model catalog unavailable" : "Call spec unavailable"}</h1>
      <p className="text-sm text-muted-foreground">{resource === "catalog" ? "The provider and model choices couldn't be loaded." : "This call spec couldn't be loaded."} Try again to open the editor.</p>
      <Button onClick={onRetry}><RotateCcw className="h-4 w-4" />Retry</Button>
    </section>}
  </main>;
}
