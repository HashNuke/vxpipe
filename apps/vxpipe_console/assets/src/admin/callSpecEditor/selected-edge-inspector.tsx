import { Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import type { TransferEdge } from "./graph";
import { InspectorRow, InspectorShell } from "./inspector-primitives";

/** Callpipe's selected-edge inspector, bound to portable transfer entries. */
export function SelectedEdgeInspector({ selectedEdge, readOnly, onDeleteEdge }: { selectedEdge: TransferEdge; readOnly: boolean; onDeleteEdge: (edge: TransferEdge) => void }) {
  return <InspectorShell title="Selected edge" subtitle={selectedEdge.locked ? "Call entry" : "Transfer destination"}>
    <div className="space-y-4">
      <dl className="space-y-3 text-sm">
        <InspectorRow label="Source" value={selectedEdge.source === "$entry" ? "Entry" : selectedEdge.source} />
        <InspectorRow label="Target" value={selectedEdge.target} />
      </dl>
      {selectedEdge.locked ? <p className="text-sm text-muted-foreground">Change the call handler in Call settings.</p>
        : <Button variant="secondary" size="sm" className="w-full justify-start text-destructive" disabled={readOnly} onClick={() => onDeleteEdge(selectedEdge)}>
          <Trash2 className="h-4 w-4" />Delete transfer
        </Button>}
    </div>
  </InspectorShell>;
}
