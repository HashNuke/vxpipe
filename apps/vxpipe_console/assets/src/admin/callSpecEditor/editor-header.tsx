import { useRef, type FormEventHandler, type ReactNode } from "react"
import { ArrowLeft, CircleAlert, Code, EllipsisVertical, LoaderCircle, Pencil, Rocket, Save } from "lucide-react"

import { TextField } from "./editor-fields"
import type { SourceIssue } from "./types"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/admin/components/ui/dialog"

import { Button } from "../components/ui/button"
import { Badge } from "../components/ui/badge"
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "../components/ui/dropdown-menu"

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
  toolbar?: ReactNode;
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
  toolbar,
}: EditorHeaderProps) {
  const busy = saving || loading || publishing;
  const disabled = busy || readOnly;
  const draftDisabled = disabled || saveDisabled || authoringDisabled;
  const openingSource = useRef(false);
  return (
    <div
      data-flow-editor-header
      className={[
        "z-10 rounded-md border border-border bg-background/95 shadow-sm backdrop-blur",
        layout === "settings"
          ? "relative"
          : "absolute left-4 right-4 top-2 lg:right-[calc(34rem+0.75rem)] lg:left-3 lg:top-3"
      ].join(" ")}
    >
      <div className="flex min-h-10 items-stretch">
      <a href={backHref} aria-label="Back to call specs" className="flex w-10 shrink-0 items-center justify-center rounded-l-md border-r border-border text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
        onClick={onBack ? (event) => { event.preventDefault(); onBack(); } : undefined}>
        <ArrowLeft className="h-4 w-4" />
      </a>
      <div className="flex min-w-0 flex-1 flex-wrap items-stretch">
        <div className="flex min-w-0 max-w-full flex-wrap items-center gap-2 px-2 py-1">
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
        <div className="ml-auto flex items-stretch">
          {issueCount > 0 && <Button variant="ghost" size="sm" onClick={onShowIssues} className="h-auto min-h-10 rounded-none border-l border-border px-3 text-destructive has-[>svg]:px-3 focus-visible:ring-inset">
            <CircleAlert className="h-4 w-4" />{issueCount} {issueCount === 1 ? "issue" : "issues"}
          </Button>}
          <div role="group" aria-label="Publish actions" className="inline-flex shrink-0 items-stretch border-l border-border">
            <Button variant="ghost" size="sm" className="h-auto min-h-10 rounded-none px-3 has-[>svg]:px-3 focus-visible:ring-inset" onClick={onPublish} disabled={disabled || authoringDisabled || revision === undefined || dirty || issueCount > 0}>
              {saving || publishing ? <LoaderCircle className="h-4 w-4 animate-spin motion-reduce:animate-none" /> : <Rocket className="h-4 w-4" />}
              {saving ? "Saving…" : publishing ? "Publishing…" : "Publish"}
            </Button>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="icon-sm" className="h-auto min-h-10 w-9 rounded-none rounded-r-md border-l border-border focus-visible:ring-inset" aria-label="More actions" disabled={draftDisabled && (!onShowSource || loading)}>
                  <EllipsisVertical className="h-4 w-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" onCloseAutoFocus={(event) => {
                if (openingSource.current) {
                  event.preventDefault();
                  openingSource.current = false;
                }
              }}>
                {onShowSource && <>
                  <DropdownMenuItem onSelect={() => { openingSource.current = true; onShowSource(); }} disabled={loading}>
                    <Code className="h-4 w-4" />JSON editor
                  </DropdownMenuItem>
                  <DropdownMenuSeparator />
                </>}
                <DropdownMenuItem onSelect={onSaveDraft} disabled={draftDisabled}>
                  <Save className="h-4 w-4" />Save as draft
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
        {jsonDraftCount > 0 && <div role="status" className="flex w-full flex-wrap items-center gap-x-2 px-2 py-1 text-xs text-muted-foreground">
          <span>Apply or discard JSON edits before saving.</span>
          <Button variant="link" size="sm" className="h-auto p-0 text-xs" onClick={onShowJsonDraft}>Review JSON edits{jsonDraftCount > 1 ? ` (${jsonDraftCount})` : ""}</Button>
        </div>}
      </div>
      </div>
      {toolbar}
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
