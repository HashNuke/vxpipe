import { useState, type ReactNode } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { ReactFlow } from "@xyflow/react";
import { FlowNode } from "./flow-node";
import { canvasGraph } from "./flow-layout";
import { editorFixture } from "./editorFixtures";
import { FlowEditorLayout } from "./flow-editor-layout";
import { addParticipant, setTransfer } from "./participants";
import { EditorTheme } from "./EditorTheme";
import { FlowEditorHeader, FlowNameDialog } from "./editor-header";
import { FlowEditorToolbar } from "./editor-toolbar";
import "../admin.css";

// Adapted from the committed Callpipe component stories. Inspector stories follow
// their respective inspector adaptations; excluded feature stories are omitted.
function StoryProviders({ children }: { children: ReactNode }) {
  return <EditorTheme><div className="relative min-h-screen bg-muted p-4">{children}</div></EditorTheme>;
}

const header = {
  backHref: "#call-specs",
  flowName: "New Patient Appointment Intake",
  revision: 3,
  publishedRevision: 2,
  onEditFlowName: () => {},
  onSaveDraft: () => {},
  onPublish: () => {},
  onShowIssues: () => {},
};
const meta = {
  title: "Vxpipe/Console/Call spec editor/Components",
  parameters: { layout: "fullscreen" },
} satisfies Meta;
export default meta;
type Story = StoryObj<typeof meta>;

export const Header: Story = {
  render: () => <StoryProviders><FlowEditorHeader {...header} dirty issueCount={2} /></StoryProviders>,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Edit call spec name" })).toBeEnabled();
    await expect(canvas.getByRole("button", { name: "Save draft" })).toBeEnabled();
    await expect(canvas.getByText("Published: 2")).toBeVisible();
  },
};
export const HeaderSaving: Story = {
  render: () => <StoryProviders><FlowEditorHeader {...header} saving /></StoryProviders>,
  play: async ({ canvasElement }) => {
    await expect(within(canvasElement).getByRole("button", { name: "Saving…" })).toBeDisabled();
  },
};
function NameDialogStory() {
  const [value, setValue] = useState("New Patient Appointment Intake");
  const [open, setOpen] = useState(true);
  return <StoryProviders><FlowNameDialog open={open} value={value} onValueChange={setValue}
    onCancel={() => setOpen(false)} onSubmit={(event) => { event.preventDefault(); setOpen(false); }} /></StoryProviders>;
}
export const NameDialog: Story = {
  render: () => <NameDialogStory />,
  play: async ({ canvasElement }) => {
    const body = within(canvasElement.ownerDocument.body);
    const dialog = await body.findByRole("dialog", { name: "Edit call spec name" });
    const input = within(dialog).getByRole("textbox", { name: "Call spec name" });
    await userEvent.clear(input);
    await userEvent.type(input, "Reception");
    await expect(input).toHaveValue("Reception");
  },
};
export const Toolbar: Story = {
  render: () => <StoryProviders><FlowEditorToolbar onAddNode={() => {}} onArrangeNodes={() => {}} /></StoryProviders>,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("toolbar", { name: "Add participants" })).toBeVisible();
    await expect(canvas.getByRole("button", { name: "Add agent" })).toBeEnabled();
  },
};

const storyNodeTypes = { flowNode: FlowNode };
export const NodeCards: Story = {
  render: () => <StoryProviders><div className="grid grid-cols-1 gap-4 rounded-md border border-border bg-background p-5 xl:grid-cols-3">
    {canvasGraph(editorFixture, "intake", { intake: 2 }).nodes.map((node) => <div key={node.id} className="relative flex h-56 min-w-0 items-center justify-center rounded-md border border-border bg-muted"><ReactFlow defaultNodes={[{ ...node, position: { x: 0, y: 0 } }]} nodeTypes={storyNodeTypes} nodesDraggable={false} nodesConnectable={false} fitView fitViewOptions={{ padding: 0.15, maxZoom: 1 }} /></div>)}
  </div></StoryProviders>,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    for (const label of ["Entry", "intake", "specialist"]) await expect(canvas.getByText(label, { exact: true })).toBeVisible();
  },
};

function CanvasShellStory({ issues }: { issues?: Record<string, number> } = {}) {
  const [document, setDocument] = useState(editorFixture);
  const [selected, setSelected] = useState<string | null>(null);
  const [edge, setEdge] = useState<string | null>(null);
  const [editingName, setEditingName] = useState(false);
  const [name, setName] = useState(document.source.name ?? "");
  const [dirty, setDirty] = useState(false);
  const title = edge ? "Selected transfer" : selected === "$entry" ? "Entry" : selected ?? "Call settings";
  return <EditorTheme><FlowEditorLayout {...header} document={document} selectedNodeId={selected} issues={issues}
    onSelectNode={(id) => { setSelected(id); setEdge(null); }} onSelectEdge={(id) => { setEdge(id); setSelected(null); }}
    onConnect={(source, target) => { setDocument((current) => setTransfer(current, source, target, true)); setDirty(true); }}
    onAddNode={(kind) => {
      let count = 1;
      while (Object.hasOwn(document.source.participants, `${kind}_${count}`)) count++;
      const key = `${kind}_${count}`;
      setDocument((current) => addParticipant(current, key, kind)); setSelected(key); setEdge(null); setDirty(true);
    }}
    onEditFlowName={() => { setName(document.source.name ?? ""); setEditingName(true); }} dirty={dirty}
    inspectorTitle={title} inspector={<div className="space-y-3 p-6"><h2 className="text-lg font-semibold">{title}</h2><p className="text-sm text-muted-foreground">{edge ? "Transfer between participants" : selected ? "Participant settings" : "Direction, defaults and call settings"}</p></div>} />
    <FlowNameDialog open={editingName} value={name} onValueChange={setName} onCancel={() => setEditingName(false)}
      onSubmit={(event) => { event.preventDefault(); setDocument((current) => ({ ...current, source: { ...current.source, name } })); setDirty(true); setEditingName(false); }} />
  </EditorTheme>;
}
export const CanvasShell: Story = { render: () => <CanvasShellStory /> };

export const CanvasIssues: Story = {
  render: () => <CanvasShellStory issues={{ $settings: 1, intake: 2 }} />,
  play: async ({ canvasElement }) => {
    await expect(within(canvasElement).getByRole("button", { name: "Call settings" })).toHaveAttribute("aria-description", "1 issue");
  },
};
