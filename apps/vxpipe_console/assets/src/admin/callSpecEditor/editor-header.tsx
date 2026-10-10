import type { FormEventHandler } from "react"
import { ArrowLeft, CircleAlert, Code, EllipsisVertical, LoaderCircle, Pencil, Rocket, Save } from "lucide-react"

import { TextField } from "./editor-fields"
import type { SourceIssue } from "./types"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/admin/components/ui/dialog"

import { Button } from "../components/ui/button"
import { Badge } from "../components/ui/badge"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../components/ui/dropdown-menu"

export type EditorHeaderProps = {
  backHref: string;
  onBack?: () => void;
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
  onShowSource?: () => void;
  jsonDraftCount?: number;
  onShowJsonDraft?: () => void;
  saveDisabled?: boolean;
  authoringDisabled?: boolean;
};

export function FlowEditorHeader({
  backHref,
  onBack,
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
  onShowSource,
  jsonDraftCount = 0,
  onShowJsonDraft,
  saveDisabled = false,
  authoringDisabled = false,
}: EditorHeaderProps) {
  const busy = saving || loading || publishing;
  const disabled = busy || readOnly;
  const draftDisabled = disabled || saveDisabled || authoringDisabled;
  return (
    <div
      data-flow-editor-header
      className={[
        "z-10 flex min-h-11 items-stretch rounded-md border border-border bg-background/95 shadow-sm backdrop-blur",
        layout === "settings"
          ? "relative"
          : "absolute left-4 right-4 top-2 lg:right-[calc(34rem+0.75rem)] lg:left-3 lg:top-3"
      ].join(" ")}
    >
      <a href={backHref} aria-label="Back to call specs" className="flex w-10 shrink-0 items-center justify-center rounded-l-md border-r border-border text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
        onClick={onBack ? (event) => { event.preventDefault(); onBack(); } : undefined}>
        <ArrowLeft className="h-4 w-4" />
      </a>
      <div className="flex min-w-0 flex-1 flex-wrap items-center gap-x-3 gap-y-2 px-3 py-2">
        <div className="flex min-w-0 max-w-full flex-wrap items-center gap-2">
          <div className="min-w-0 max-w-full sm:max-w-64">
            <h1 className="sr-only">{flowName || "New call spec"}</h1>
            <button
              type="button"
              className="flex max-w-full items-center gap-2 rounded-md px-1.5 py-1 text-left text-sm font-semibold text-foreground transition-colors hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              onClick={onEditFlowName}
              aria-label="Edit call spec name"
              disabled={disabled}
            >
              <span className="min-w-0 truncate">{flowName || "New call spec"}</span>
              <Pencil className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
            </button>
          </div>
        <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
          {revision !== undefined && <Badge variant="secondary" title={`Revision ${revision}`}>v{revision}</Badge>}
          {publishedRevision !== undefined && <Badge variant="outline">Published: {publishedRevision}</Badge>}
          {dirty && <span>Unsaved changes</span>}
          {readOnly && <Badge variant="outline">Read only</Badge>}
        </div>
        </div>
        <div className="ml-auto flex flex-wrap items-center gap-1.5 sm:gap-2">
          {issueCount > 0 && <Button variant="outline" size="sm" onClick={onShowIssues} className="text-destructive">
            <CircleAlert className="h-4 w-4" />{issueCount} {issueCount === 1 ? "issue" : "issues"}
          </Button>}
          {onShowSource && <Button variant="outline" size="sm" onClick={onShowSource} disabled={loading}><Code className="h-4 w-4" />JSON</Button>}
          <div role="group" aria-label="Publish actions" className="inline-flex shrink-0 items-center">
            <Button size="sm" className="relative h-8 rounded-r-none px-2 focus-visible:z-10 disabled:text-primary-foreground/50 disabled:opacity-100 sm:px-3" onClick={onPublish} disabled={disabled || authoringDisabled || revision === undefined || dirty || issueCount > 0}>
              {saving || publishing ? <LoaderCircle className="h-4 w-4 animate-spin motion-reduce:animate-none" /> : <Rocket className="h-4 w-4" />}
              {saving ? "Saving…" : publishing ? "Publishing…" : "Publish"}
            </Button>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button size="icon-sm" className="relative rounded-l-none border-l border-primary-foreground/25 focus-visible:z-10 disabled:text-primary-foreground/50 disabled:opacity-100" aria-label="More actions" disabled={draftDisabled}>
                  <EllipsisVertical className="h-4 w-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onSelect={onSaveDraft} disabled={draftDisabled}>
                  <Save className="h-4 w-4" />Save as draft
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
        {jsonDraftCount > 0 && <div role="status" className="flex w-full flex-wrap items-center gap-x-2 text-xs text-muted-foreground">
          <span>Apply or discard JSON edits before saving.</span>
          <Button variant="link" size="sm" className="h-auto p-0 text-xs" onClick={onShowJsonDraft}>Review JSON edits{jsonDraftCount > 1 ? ` (${jsonDraftCount})` : ""}</Button>
        </div>}
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
  issues,
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
  issues?: SourceIssue[];
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
          <TextField
            value={value}
            onChange={onValueChange}
            label={nameLabel}
            labelHidden
            path={["name"]}
            issues={issues}
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
