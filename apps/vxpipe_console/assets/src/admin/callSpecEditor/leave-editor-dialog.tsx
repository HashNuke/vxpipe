import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "../components/ui/alert-dialog";

export function LeaveEditorDialog({ intent, onCancel, onConfirm }: { intent: "leave" | "reload" | null; onCancel: () => void; onConfirm: () => void }) {
  return <AlertDialog open={intent !== null} onOpenChange={(open) => { if (!open) onCancel(); }}><AlertDialogContent>
    <AlertDialogHeader><AlertDialogTitle>{intent === "reload" ? "Reload and discard changes?" : "Leave with unsaved changes?"}</AlertDialogTitle>
      <AlertDialogDescription>Your changes in this tab have not been saved. {intent === "reload" ? "Reloading replaces them with the latest saved revision." : "Leaving this page discards them."}</AlertDialogDescription>
    </AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Keep editing</AlertDialogCancel>
      <AlertDialogAction onClick={onConfirm}>{intent === "reload" ? "Reload latest revision" : "Leave page"}</AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent></AlertDialog>;
}
