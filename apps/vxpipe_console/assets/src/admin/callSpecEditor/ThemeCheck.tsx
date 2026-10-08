import { useId, useState } from "react";
import { EditorTheme } from "./EditorTheme";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Label } from "../components/ui/label";
import { Textarea } from "../components/ui/textarea";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "../components/ui/dialog";
import { Popover, PopoverContent, PopoverTrigger } from "../components/ui/popover";
import { Badge } from "../components/ui/badge";
import { Switch } from "../components/ui/switch";

export function ThemeCheck({ theme = "dark" }: { theme?: "dark" | "light" }) {
  const id = useId();
  const [record, setRecord] = useState(false);
  return <EditorTheme theme={theme}>
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-6 p-6 sm:p-10">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold text-foreground">Call spec controls</h1>
        <Badge variant="secondary">Draft</Badge>
      </header>
      <section className="space-y-5 rounded-lg border border-border bg-card p-5 text-card-foreground shadow-sm">
        <div className="space-y-2"><Label htmlFor={`${id}-name`}>Call spec name</Label><Input id={`${id}-name`} defaultValue="Reception" /></div>
        <div className="space-y-2"><Label htmlFor={`${id}-prompt`}>Agent prompt</Label><Textarea id={`${id}-prompt`} defaultValue="Help the caller and transfer when needed." /><p className="text-sm text-muted-foreground">Tell the agent how to help the caller.</p></div>
        <div className="flex items-center justify-between gap-4"><Label htmlFor={`${id}-record`}>Record audio</Label><Switch id={`${id}-record`} checked={record} onCheckedChange={setRecord} /></div>
        <div className="flex flex-wrap gap-2">
          <Button>Save draft</Button><Button disabled>Publish</Button>
          <Dialog><DialogTrigger asChild><Button variant="outline">Edit name</Button></DialogTrigger><DialogContent>
            <DialogHeader><DialogTitle>Edit call spec name</DialogTitle><DialogDescription>This dialog uses the same Console theme as the editor.</DialogDescription></DialogHeader>
            <Label htmlFor={`${id}-dialog-name`}>Name</Label><Input id={`${id}-dialog-name`} defaultValue="Reception" />
          </DialogContent></Dialog>
          <Popover><PopoverTrigger asChild><Button variant="secondary">Model details</Button></PopoverTrigger><PopoverContent className="space-y-2"><p className="font-medium">Recommended model</p><p className="text-sm text-muted-foreground">Provider recommendations come from the installed catalog.</p></PopoverContent></Popover>
        </div>
        <div className="space-y-2"><Label htmlFor={`${id}-invalid`}>Destination key</Label><Input id={`${id}-invalid`} aria-invalid defaultValue="" aria-describedby={`${id}-error`} /><p id={`${id}-error`} className="text-sm text-destructive">Choose a destination key.</p></div>
      </section>
    </main>
  </EditorTheme>;
}
