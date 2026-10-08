import type { FormEventHandler } from "react"
import { ArrowLeft, CircleAlert, Pencil, Rocket, Save } from "lucide-react"

import { Input } from "@/admin/components/ui/input"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/admin/components/ui/dialog"

import { Button } from "../components/ui/button"
import { Badge } from "../components/ui/badge"

export type EditorHeaderProps = {
  backHref: string;
  flowName?: string | null;
  revision?: number;
  publishedRevision?: number;
  dirty?: boolean;
  issueCount?: number;
  readOnly?: boolean;
  saving?: boolean;
  publishing?: boolean;
  loading?: boolean;
  layout?: "canvas" | "settings";
  onEditFlowName: () => void;
  onSaveDraft: () => void;
  onPublish: () => void;
  onShowIssues: () => void;
};

export function FlowEditorHeader({
  backHref,
  flowName,
  saving,
  publishing = false,
  loading,
  layout = "canvas",
  revision,
  publishedRevision,
  dirty = false,
  issueCount = 0,
  readOnly = false,
  onEditFlowName,
  onSaveDraft,
  onPublish,
  onShowIssues,
}: EditorHeaderProps) {
  const busy = saving || loading || publishing;
  const disabled = busy || readOnly;
  return (
    <div
      data-flow-editor-header
      className={[
        "z-10 flex min-h-11 flex-wrap items-center justify-between gap-3 rounded-md border border-border bg-background/95 px-3 py-2 shadow-sm backdrop-blur",
        layout === "settings"
          ? "relative"
          : "absolute left-4 right-4 top-2 lg:right-[calc(34rem+0.75rem)] lg:left-3 lg:top-3"
      ].join(" ")}
    >
      <div className="flex min-w-0 items-center gap-2">
        <Button asChild variant="secondary" size="icon" className="h-8 w-8 shrink-0" aria-label="Back to call specs">
          <a href={backHref} aria-label="Back to call specs">
            <ArrowLeft className="h-4 w-4" />
          </a>
        </Button>
        <div className="min-w-0">
          <h1 className="sr-only">{flowName || "New call spec"}</h1>
          <button
            type="button"
            className="-ml-1 flex max-w-full items-center gap-2 rounded-md px-1.5 py-1 text-left text-sm font-semibold text-foreground transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            onClick={onEditFlowName}
            aria-label="Edit call spec name"
            disabled={disabled}
          >
            <span className="min-w-0 truncate">{flowName || "New call spec"}</span>
            <Pencil className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          </button>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
        {revision !== undefined && <Badge variant="secondary">Revision {revision}</Badge>}
        {publishedRevision !== undefined && <Badge variant="outline">Published: {publishedRevision}</Badge>}
        {dirty && <span>Unsaved changes</span>}
        {readOnly && <Badge variant="outline">Read only</Badge>}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {issueCount > 0 && <Button variant="outline" size="sm" onClick={onShowIssues} className="text-destructive">
          <CircleAlert className="h-4 w-4" />{issueCount} {issueCount === 1 ? "issue" : "issues"}
        </Button>}
        <Button variant="secondary" size="sm" className="h-8 px-3" onClick={onSaveDraft} disabled={disabled}>
          <Save className="h-4 w-4" />
          {saving ? "Saving…" : "Save draft"}
        </Button>
        <Button size="sm" className="h-8 px-3" onClick={onPublish} disabled={disabled}>
          <Rocket className="h-4 w-4" />
          {publishing ? "Publishing…" : "Publish"}
        </Button>
      </div>
    </div>
  )
}

export function FlowNameDialog({
  open,
  value,
  title = "Edit call spec name",
  nameLabel = "Call spec name",
  cancelLabel = "Cancel",
  saveLabel = "Save name",
  onValueChange,
  onCancel,
  onSubmit
}: {
  open: boolean;
  value: string;
  title?: string;
  nameLabel?: string;
  cancelLabel?: string;
  saveLabel?: string;
  onValueChange: (value: string) => void;
  onCancel: () => void;
  onSubmit: FormEventHandler<HTMLFormElement>;
}) {
  return (
    <Dialog open={open} onOpenChange={(nextOpen) => !nextOpen && onCancel()}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={onSubmit} className="space-y-4">
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            <DialogDescription>Choose a name to identify this call spec.</DialogDescription>
          </DialogHeader>
          <Input
            value={value}
            autoFocus
            onChange={(event) => onValueChange(event.target.value)}
            aria-label={nameLabel}
          />
          <DialogFooter>
            <Button variant="secondary" type="button" onClick={onCancel}>
              {cancelLabel}
            </Button>
            <Button type="submit">
              {saveLabel}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
