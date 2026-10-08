import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, within } from "storybook/test";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { AgentInspector, type AgentInspectorTab } from "./agent-inspector";
import { FlowLevelInspector, type CallSettingsTab } from "./flow-level-inspector";
import { EditorTheme } from "./EditorTheme";
import { FlowEditorHeader } from "./editor-header";
import { EditorToast } from "./editor-toast";
import { actionOutcome, locateIssue, type ActionFeedback, type ActionResult } from "./errorPresentation";
import { editorFixture } from "./editorFixtures";
import { backendIssue, mergeIssues, retainBackendIssue } from "./issues";
import { IssuesDrawer } from "./issues-drawer";
import type { IssueRequest } from "./issue-context";
import { SourceView } from "./source-view";
import type { SourceDocument, SourceIssue } from "./types";
import { validateSource } from "./validation";
import "../admin.css";

const initial = structuredClone(editorFixture);
initial.source.defaults = { capabilities: { model_inference: { provider: "google", model: "gemini-2.5-flash" } } };
initial.source.participants.intake = { type: "agent", prompt: "Help the caller.", tools: { slots: { type: "mcp", integration: "calendar", tool: "find_slots" } } };
const invalid = structuredClone(initial);
if (invalid.source.participants.intake?.type === "agent") invalid.source.participants.intake.prompt = "";
invalid.source.limits = { max_duration_ms: -1 };
const promptResult: ActionResult = { status: 422, error: { code: "invalid_call_spec", path: ["participants", "intake", "prompt"], reason: "is required" } };
const toolResult: ActionResult = { status: 422, error: { code: "invalid_call_spec", path: ["participants", "intake", "tools", "slots", "tool"], reason: "This tool is not available from the integration." } };
type Props = { theme: "light" | "dark"; initial: SourceDocument; result?: ActionResult; drawer?: boolean; sourceOpen?: boolean; reveal?: boolean };
function ErrorPresentationStory({ theme, initial, result, drawer = false, sourceOpen = false, reveal = false }: Props) {
  const [document, setDocument] = useState(initial);
  const [serverIssue, setServerIssue] = useState(result ? backendIssue(initial.source, result) : undefined);
  const [feedback, setFeedback] = useState<ActionFeedback | null>(result && !reveal ? actionOutcome(initial.source, "save", result) : null);
  const [issuesOpen, setIssuesOpen] = useState(drawer);
  const [jsonOpen, setJsonOpen] = useState(sourceOpen);
  const [tab, setTab] = useState(reveal ? "tools" : "prompt");
  const [settings, setSettings] = useState(false);
  const [request, setRequest] = useState<IssueRequest | undefined>(reveal && result?.error?.path ? { id: 1, path: result.error.path } : undefined);
  const client = validateSource(document.source);
  const issues = mergeIssues(client, serverIssue);
  function change(next: SourceDocument) { setServerIssue(retainBackendIssue(serverIssue, document.source, next.source)); setDocument(next); }
  function show(issue: SourceIssue) {
    const location = locateIssue(document.source, issue.path);
    if (!location) { setIssuesOpen(true); return; }
    setSettings(location.nodeId === "$settings"); setTab(location.tab); setRequest((previous) => ({ id: (previous?.id ?? 0) + 1, path: issue.path })); setIssuesOpen(false);
  }
  const props = { document, onChange: change, issues, focusRequest: request, catalog: modelCatalogFixture, lookups: { telephonyServices: [], credentialNames: {}, mcpIntegrations: ["calendar"] } };
  return <EditorTheme theme={theme}><main className="min-h-screen bg-muted sm:p-6"><div className="mx-auto flex h-dvh w-full max-w-[34rem] flex-col overflow-hidden border bg-background sm:h-[calc(100dvh-3rem)] sm:rounded-md">
    <FlowEditorHeader backHref="#call-specs" layout="settings" flowName={document.source.name} revision={3} readOnly={document.readOnly} issueCount={client.length}
      onEditFlowName={() => { setSettings(true); setTab("direction"); }} onShowSource={() => setJsonOpen(true)} onShowIssues={() => setIssuesOpen(true)}
      onSaveDraft={() => setFeedback(actionOutcome(document.source, "save", client.length ? { clientIssues: client } : result ?? { status: 201, revision: 4 }))}
      onPublish={() => setFeedback(actionOutcome(document.source, "publish", { status: 200, revision: 3 }))} />
    <div className="min-h-0 flex-1">{settings ? <FlowLevelInspector {...props} tab={tab as CallSettingsTab} onTabChange={(tab) => { setTab(tab); setRequest(undefined); }} />
      : <AgentInspector {...props} participantKey="intake" tab={tab as AgentInspectorTab} onTabChange={(tab) => { setTab(tab); setRequest(undefined); }} />}</div>
    <IssuesDrawer open={issuesOpen} onOpenChange={setIssuesOpen} source={document.source} issues={issues} onShow={show} />
    <SourceView open={jsonOpen} onOpenChange={setJsonOpen} source={document.source} onFeedback={setFeedback} />
    <EditorToast feedback={feedback} onDismiss={() => setFeedback(null)} onAction={(action) => {
      if (action === "show") { const issue = feedback?.issue; if (issue) show({ code: issue.code, path: issue.path ?? [], reason: issue.reason ?? feedback!.message }); }
      else setFeedback(null);
    }} />
  </div></main></EditorTheme>;
}
const meta = { title: "Vxpipe/Console/Call spec editor/Error presentation", component: ErrorPresentationStory, parameters: { layout: "fullscreen" }, args: { theme: "dark", initial } } satisfies Meta<typeof ErrorPresentationStory>;
export default meta;
type Story = StoryObj<typeof meta>;
export const FieldErrors: Story = { args: { initial: invalid } };
export const IssuesList: Story = { args: { initial: invalid, drawer: true } };
export const BackendError: Story = { args: { result: promptResult }, play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body); await userEvent.click(await body.findByRole("button", { name: "Show" }));
  await expect(body.getByRole("textbox", { name: "Prompt" })).toHaveFocus();
} };
export const UnmappedBackendError: Story = { args: { result: { status: 422, error: { code: "invalid_call_spec", path: ["future_policy"], reason: "A new server policy requires review." } } } };
export const ToolFieldError: Story = { args: { result: toolResult, reveal: true } };
export const SourceJson: Story = { args: { sourceOpen: true } };
export const ServicesRecovery: Story = { args: { result: { status: 422, error: { code: "provider_credential_unavailable", path: ["defaults", "capabilities", "model_inference"] } } } };
export const ReloadRecovery: Story = { args: { result: { status: 409, error: { code: "revision_conflict" } } } };
export const RetryRecovery: Story = { args: { result: { status: 503, error: { code: "call_spec_authoring_unavailable" } } } };
