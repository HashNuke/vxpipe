import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { Button } from "../components/ui/button";
import { EditorTheme } from "./EditorTheme";
import { FlowEditorLayout } from "./flow-editor-layout";
import { FlowNameDialog } from "./editor-header";
import { editorStoryFixture } from "./editorFixtures";
import "../admin.css";

type Content = { name: string; prompt: string };
type Version = { number: number; content: Content; date: string };
type Props = { state: "published" | "unpublished" | "draft" | "unsaved"; theme: "dark" | "light" };
const initialContent: Content = { name: "New Patient Appointment Intake", prompt: "Welcome the caller and help them schedule a new patient appointment." };
const revisedContent: Content = { ...initialContent, prompt: `${initialContent.prompt} Confirm their preferred appointment time before finishing.` };
const currentDate = () => new Date().toISOString();
const sameContent = (left: Content, right: Content) => left.name === right.name && left.prompt === right.prompt;

/** Story-only publication model. No API writes or changes to persisted revision semantics. */
function PublicationPreview({ state, theme }: Props) {
  const [versions, setVersions] = useState<Version[]>(() => state === "draft" ? [] : [
    { number: 6, content: initialContent, date: "2026-11-17T10:30:00Z" },
    { number: 5, content: { ...initialContent, prompt: "Welcome the caller and ask what kind of appointment they need." }, date: "2026-11-16T15:10:00Z" },
    { number: 4, content: initialContent, date: "2026-11-15T09:20:00Z" },
  ]);
  const [saved, setSaved] = useState(state === "unpublished" ? revisedContent : initialContent);
  const [content, setContent] = useState(state === "unpublished" || state === "unsaved" ? revisedContent : initialContent);
  const [lastSaved, setLastSaved] = useState("2026-11-17T11:45:00Z");
  const [nameDraft, setNameDraft] = useState<string>();
  const [feedback, setFeedback] = useState("");
  const published = versions.at(0);
  const dirty = !sameContent(content, saved);
  const unpublished = published !== undefined && !sameContent(saved, published.content);
  const document = { ...editorStoryFixture, source: { ...editorStoryFixture.source, name: content.name } };

  function save() { setSaved(content); setLastSaved(currentDate()); setFeedback("Draft saved"); }
  function publish() {
    setSaved(content);
    setLastSaved(currentDate());
    if (!published || !sameContent(content, published.content)) {
      const number = (published?.number ?? 0) + 1;
      setVersions(current => [{ number, content, date: currentDate() }, ...current]);
      setFeedback(`Version ${number} published`);
    } else setFeedback("No changes to publish");
  }

  return <EditorTheme theme={theme}>
    <FlowEditorLayout document={document} backHref="#" onBack={() => setFeedback("You are viewing the publication preview.")}
      revision={1} publishedRevision={published?.number} dirty={dirty}
      publication={{ version: published?.number ?? null, revision: published?.number ?? null,
        unpublishedChanges: unpublished, draftSavedAt: lastSaved,
        history: versions.slice(0, 3).map(version => ({ version: version.number, publishedAt: version.date })),
      }}
      onEditFlowName={() => setNameDraft(content.name)} onSaveDraft={save} onPublish={publish} onShowIssues={() => {}}
      onAddNode={() => setFeedback("This preview focuses on publication status. Edit the prompt to try saving and publishing.")}
      selectedNodeId="intake" onSelectNode={() => {}} onSelectEdge={() => {}} onConnect={() => {}}
      inspectorTitle="Intake agent"
      inspector={<div className="space-y-6 p-6">
        <div><h2 className="text-base font-semibold">Intake agent</h2><p className="mt-1 text-sm text-muted-foreground">New patient appointments</p></div>
        <div className="space-y-2"><label htmlFor="preview-prompt" className="text-sm font-medium">Prompt</label>
          <textarea id="preview-prompt" value={content.prompt} onChange={event => { setContent({ ...content, prompt: event.target.value }); setFeedback(""); }}
            className="min-h-48 w-full resize-y rounded-md border border-input bg-background p-3 text-sm leading-relaxed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" />
        </div>
        <div className="flex flex-wrap items-center gap-3"><Button variant="outline" onClick={save} disabled={!dirty}>Save draft</Button><span role="status" className="text-xs text-muted-foreground">{dirty ? "Unsaved changes" : feedback || "All changes saved"}</span></div>
        <p className="text-xs leading-relaxed text-muted-foreground">Interactive preview. Edit the prompt, save a draft, then publish. Open the published badge to explore version history.</p>
      </div>} />
    <FlowNameDialog open={nameDraft !== undefined} value={nameDraft ?? ""} onValueChange={setNameDraft} onCancel={() => setNameDraft(undefined)}
      onSubmit={event => { event.preventDefault(); setContent({ ...content, name: nameDraft ?? content.name }); setNameDraft(undefined); }} />
  </EditorTheme>;
}
const meta = {
  title: "Vxpipe/Console/Call spec editor/Publication preview",
  component: PublicationPreview,
  parameters: { layout: "fullscreen" },
  args: { state: "unpublished", theme: "dark" },
} satisfies Meta<typeof PublicationPreview>;
export default meta;
type Story = StoryObj<typeof meta>;
export const UnpublishedChanges: Story = {};
export const Published: Story = { args: { state: "published" } };
export const NeverPublished: Story = { args: { state: "draft" } };
export const UnsavedEdits: Story = { args: { state: "unsaved" } };
export const Light: Story = { args: { theme: "light" } };
export const VersionHistory: Story = { play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body);
  await userEvent.click(body.getByRole("button", { name: "v6 · Unpublished changes" }));
  await expect(body.getByRole("dialog", { name: "Version history" })).toBeVisible();
  await expect(within(body.getByRole("dialog", { name: "Version history" })).getByText("Unpublished changes")).toBeVisible();
} };
export const SaveThenPublish: Story = { args: { state: "published" }, play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body);
  await userEvent.type(body.getByRole("textbox", { name: "Prompt" }), " Ask for a callback number.");
  await userEvent.click(body.getByRole("button", { name: "Save draft" }));
  await expect(body.getByRole("button", { name: "v6 · Unpublished changes" })).toBeVisible();
  await expect(body.getByRole("button", { name: "v6 · Unpublished changes" })).toBeVisible();
  await userEvent.type(body.getByRole("textbox", { name: "Prompt" }), " Confirm it.");
  await userEvent.click(body.getByRole("button", { name: "Save draft" }));
  await expect(body.getByRole("button", { name: "v6 · Unpublished changes" })).toBeVisible();
  await userEvent.click(body.getByRole("button", { name: "Publish" }));
  await expect(body.getByRole("button", { name: "v7 Published" })).toBeVisible();
  await expect(body.queryByRole("button", { name: /Unpublished changes/ })).not.toBeInTheDocument();
} };
