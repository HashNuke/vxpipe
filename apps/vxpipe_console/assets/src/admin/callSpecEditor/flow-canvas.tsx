import { useMemo, useState } from "react";
import { Background, Controls, ReactFlow, type XYPosition } from "@xyflow/react";
import { FitCanvasOnResize } from "./fit-canvas-on-resize";
import { FlowNode } from "./flow-node";
import { canvasGraph, canConnectParticipants, flowFitViewOptions } from "./flow-layout";
import type { SourceDocument } from "./types";

const nodeTypes = { flowNode: FlowNode };
export type FlowCanvasProps = {
  document: SourceDocument;
  selectedNodeId: string | null;
  issues?: Record<string, number>;
  onConnect: (source: string, target: string) => void;
  onSelectNode: (id: string | null) => void;
  onSelectEdge: (id: string) => void;
};

export function FlowCanvas({ document, selectedNodeId, issues, onConnect, onSelectNode, onSelectEdge }: FlowCanvasProps) {
  const [positions, setPositions] = useState<Record<string, { position?: XYPosition; measured?: { width: number; height: number } }>>({});
  const graph = useMemo(() => canvasGraph(document, selectedNodeId, issues), [document, selectedNodeId, issues]);
  const nodes = useMemo(() => graph.nodes.map((node) => ({ ...node, ...positions[node.id] })), [graph, positions]);
  return (
    <div data-flow-editor-canvas className="absolute inset-y-0 left-0 right-0 lg:right-[34rem]">
      <ReactFlow
        nodes={nodes}
        edges={graph.edges}
        nodeTypes={nodeTypes}
        onNodesChange={(changes) => setPositions((current) => {
          let next = current;
          for (const change of changes) {
            if (change.type !== "position" && change.type !== "dimensions") continue;
            const previous = current[change.id];
            if (change.type === "position" && change.position && (previous?.position?.x !== change.position.x || previous?.position?.y !== change.position.y)) {
              next = { ...next, [change.id]: { ...next[change.id], position: change.position } };
            }
            if (change.type === "dimensions" && change.dimensions && (previous?.measured?.width !== change.dimensions.width || previous?.measured?.height !== change.dimensions.height)) {
              next = { ...next, [change.id]: { ...next[change.id], measured: change.dimensions } };
            }
          }
          return next;
        })}
        isValidConnection={({ source, target }) => canConnectParticipants(document, source, target)}
        onConnect={({ source, target }) => { if (canConnectParticipants(document, source, target)) onConnect(source, target); }}
        onNodeClick={(_, node) => onSelectNode(node.id)}
        onEdgeClick={(_, edge) => onSelectEdge(edge.id)}
        onPaneClick={() => onSelectNode(null)}
        deleteKeyCode={null}
        fitView
        fitViewOptions={flowFitViewOptions}
      >
        <FitCanvasOnResize />
        <Background color="var(--border)" gap={20} />
        <Controls showInteractive={false} className="bottom-40 lg:bottom-0" />
      </ReactFlow>
    </div>
  );
}
