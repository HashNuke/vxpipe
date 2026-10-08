import { useRef } from "react";
import { Button } from "../components/ui/button";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "../components/ui/sheet";
import { locateIssue } from "./errorPresentation";
import type { CallSpecSource, SourceIssue } from "./types";
export function IssuesDrawer({ open, onOpenChange, source, issues, onShow }: { open: boolean; onOpenChange: (open: boolean) => void; source: CallSpecSource; issues: SourceIssue[]; onShow: (issue: SourceIssue) => void }) {
  const showing = useRef(false);
  const opener = useRef<HTMLElement | null>(null);
  return <Sheet open={open} onOpenChange={onOpenChange}><SheetContent className="w-full overflow-auto sm:max-w-lg" onOpenAutoFocus={() => { opener.current = document.activeElement instanceof HTMLElement ? document.activeElement : null; }} onCloseAutoFocus={(event) => { event.preventDefault(); if (!showing.current) opener.current?.focus(); showing.current = false; }}>
    <SheetHeader><SheetTitle>Call spec issues</SheetTitle><SheetDescription>Choose Show to open the relevant settings.</SheetDescription></SheetHeader>
    <div className="space-y-3 px-4 pb-4">{issues.map((issue, index) => <section key={index} className="space-y-2 rounded-md border p-3">
      <h3 className="wrap-anywhere text-sm font-medium">{locateIssue(source, issue.path)?.label ?? "Call spec"}</h3>
      <p className="wrap-anywhere text-sm text-muted-foreground">{issue.reason}</p>
      <Button variant="outline" size="sm" onClick={() => { showing.current = locateIssue(source, issue.path) !== null; onShow(issue); }}>Show</Button>
    </section>)}{!issues.length && <p className="text-sm text-muted-foreground">No issues found.</p>}</div>
  </SheetContent></Sheet>;
}
