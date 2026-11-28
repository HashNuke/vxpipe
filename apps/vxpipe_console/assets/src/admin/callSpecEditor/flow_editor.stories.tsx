import { StoryNavigationContext, storyNavigation } from "../stories/storyNavigation";
import { StoryPageBreadcrumbs } from "../stories/StoryPageBreadcrumbs";
import { demoTenant } from "../callSpecFixtures";
import { toolCatalogFixture } from "./toolCatalogFixture";
import { storyPhoneNumbers } from "./phone-number-fixtures";
import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, waitFor, within } from "storybook/test";
import { Button } from "../components/ui/button";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { VoiceCatalogContext } from "../voiceCatalog";
import { storyVoiceCatalog } from "../voiceCatalogFixtures";
import { EditorPageState } from "./editor-page-state";
import type { EditorResult } from "./editor-state";
import { EditorTheme } from "./EditorTheme";
import { CallSpecEditor } from "./flow-editor";
import { NewCallSpec } from "./new-call-spec";
import type { SourceDocument } from "./types";
import { pageSnapshot, type EditorScenario } from "./page-fixtures";
import "../admin.css";

import { setAgentModelMode } from "./agent-models";

type Props = { transferExample?: boolean; guardrailsExample?: boolean; guardrailMode?: "llm" | "speech_to_speech"; conversationLanguages?: string[]; theme: "dark" | "light"; scenario: EditorScenario; outcome?: EditorResult; pageStatus?: "loading" | "spec-error" | "catalog-error" };
// Adapted from Callpipe's flow_editor.stories: whole-page fixtures and real UI actions.
function FlowEditorStory({ theme, scenario, outcome, pageStatus, conversationLanguages, transferExample, guardrailsExample, guardrailMode = "llm" }: Props) {
  const [destination, setDestination] = useState<string>();
  const [created, setCreated] = useState<SourceDocument>();
  const [retried, setRetried] = useState(false);
  const [revision, setRevision] = useState(() => pageSnapshot(scenario).saved?.revision ?? 0);
  const snapshot = scenario === "new" && created ? { document: created } : pageSnapshot(scenario);
  if (transferExample) {
    snapshot.document = setAgentModelMode(snapshot.document, "intake", guardrailMode, modelCatalogFixture);
    const { participants } = snapshot.document.source;
    participants.scheduling = { type: "agent", prompt: "Help the caller arrange a follow-up appointment. Confirm their preferred date and time, then repeat the booking details." };
    participants.billing = { type: "agent", prompt: "Help the caller with billing questions. Ask which appointment they are calling about before discussing their account." };
    if (participants.intake?.type === "agent") participants.intake.transfers = ["specialist", "scheduling"];
  }
  if (guardrailsExample) {
    const source = snapshot.document.source;
    source.schema_version = "20261128.01";
    source.defaults ??= {};
    source.defaults.capabilities ??= {};
    source.defaults.capabilities.model_inference ??= { provider: "google", model: "gemini-2.5-flash" };
    source.defaults.capabilities.text_to_speech ??= { provider: "deepgram", model: "flux", options: { voice: "hannah" } };
    source.defaults.capabilities.decisions ??= { provider: "openai", model: "gpt-6-luna" };
    const intake = source.participants.intake;
    if (intake?.type === "agent") intake.guardrails = {
      before_turn: [{ question: "Is the caller asking about their own account?", required_answer: "yes" }],
      after_turn: [{ question: "Does this response disclose another patient’s details?", required_answer: "no", probability_threshold: 0.75, response: "I can only discuss your own account." }],
      before_outgoing_transfer: [{ question: "Is the requested destination unrelated to the caller’s issue?", required_answer: "no", response: "Ask which department the caller needs." }],
    };
    const scheduling = source.participants.scheduling;
    if (scheduling?.type === "agent") scheduling.guardrails = {
      before_outgoing_transfer: [{ question: "Is the appointment reference missing?", required_answer: "yes" }],
    };
  }
  if (conversationLanguages) snapshot.document.source.conversation_languages = conversationLanguages;
  return <StoryNavigationContext value={storyNavigation(`/t/${demoTenant.key}/editor`, setDestination, demoTenant)}><EditorTheme theme={theme}>{destination ? <main className="grid min-h-dvh place-content-center gap-4 bg-background p-6">
    <h1 className="text-lg font-semibold">{destination.endsWith("/dashboard") ? "Dashboard" : destination === "#services" ? "Tenant services" : "Call specs"}</h1>
    <p className="text-sm text-muted-foreground">Navigation confirmed. Return to the editor to continue the prototype.</p>
    <Button variant="outline" onClick={() => setDestination(undefined)}>Return to editor</Button>
  </main> : pageStatus && !retried ? <EditorPageState status={pageStatus === "loading" ? "loading" : "error"} resource={pageStatus === "catalog-error" ? "catalog" : "spec"} backHref="#call-specs" onRetry={() => setRetried(true)} />
    : scenario === "new" && !created ? <><div className="px-4 pt-4 sm:px-6"><StoryPageBreadcrumbs items={[{ label: "Call Specs", href: "#call-specs" }, { label: "New call spec" }]} /></div><NewCallSpec catalog={modelCatalogFixture} services={[{ key: "office-phone", name: "Office phone", provider: "telnyx" as const }]} servicesHref="#services" onCreate={setCreated} onCancel={() => setDestination("#call-specs")} /></>
    : <CallSpecEditor key={scenario} snapshot={snapshot} catalog={modelCatalogFixture} lookups={{ phoneNumbers: storyPhoneNumbers, telephonyServices: [{ key: "office-phone", name: "Office phone", provider: "telnyx" as const }], credentialNames: { google: ["primary"] }, mcpIntegrations: ["calendar"], toolCatalog: toolCatalogFixture }}
      backHref="#call-specs" servicesHref="#services" onNavigate={setDestination} onReload={async () => ({ ...pageSnapshot("default"), saved: { callSpecId: "appointments", revision: revision + 1, publishedRevision: null } })}
      execute={async (request) => {
        if (outcome) return outcome;
        if (request.action === "publish") return { status: 200, revision: request.revision };
        const next = revision + 1; setRevision(next);
        return { status: 201, revision: next, callSpecId: "appointments" };
      }} />}</EditorTheme></StoryNavigationContext>;
}
const meta = { title: "Vxpipe/Console/Call spec editor/Page", component: FlowEditorStory, decorators: [Story => <VoiceCatalogContext.Provider value={storyVoiceCatalog}><Story /></VoiceCatalogContext.Provider>], parameters: { layout: "fullscreen" }, args: { theme: "dark", scenario: "default" } } satisfies Meta<typeof FlowEditorStory>;
export default meta;
type Story = StoryObj<typeof meta>;

async function saveDraft(body: ReturnType<typeof within>) {
  await userEvent.click(body.getByRole("button", { name: "More actions" }));
  await userEvent.click(await body.findByRole("menuitem", { name: "Save as draft" }));
}

function actionStory(outcome: EditorResult, message: string, action: "Save as draft" | "Publish" = "Save as draft", scenario: EditorScenario = "default"): Story {
  return { args: { outcome, scenario }, play: async ({ canvasElement }) => {
    const body = within(canvasElement.ownerDocument.body);
    if (action === "Save as draft") await saveDraft(body);
    else await userEvent.click(body.getByRole("button", { name: action }));
    await expect(body.findByText(message)).resolves.toBeVisible();
  } };
}
export const Default: Story = { play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body);
  await expect(body.getByRole("heading", { name: "New Patient Appointment Intake" })).toBeInTheDocument();
  await expect(body.getByRole("button", { name: "More actions" })).toBeEnabled();
} };
export const EntryOpensCallSettings: Story = { play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body);
  const models = body.queryByRole("tab", { name: "Models" });
  if (models) await userEvent.click(models);
  await userEvent.click(await body.findByText("Entry", { exact: true }));
  await expect(body.findByRole("tab", { name: "Connection" })).resolves.toHaveAttribute("aria-selected", "true");
  await expect(body.getByRole("combobox", { name: "Handled by" })).toBeVisible();
  await expect(body.queryByRole("button", { name: "Participant JSON" })).not.toBeInTheDocument();
} };
export const Loading: Story = { args: { pageStatus: "loading" } };
export const LoadFailure: Story = { args: { pageStatus: "spec-error" } };
export const CatalogFailure: Story = { args: { pageStatus: "catalog-error" } };
export const NewSpec: Story = { args: { scenario: "new" } };
export const ClientValidationErrors: Story = { args: { scenario: "invalid" } };
export const SaveBlocked: Story = { args: { scenario: "invalid" }, play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body); await saveDraft(body);
  await expect(body.getByText("Fix 2 issues before saving")).toBeVisible();
} };
export const Saved: Story = actionStory({ status: 201, revision: 4 }, "Draft saved");
export const Published: Story = actionStory({ status: 200, revision: 3 }, "Published", "Publish");
export const BackendFieldError: Story = actionStory({ status: 422, error: { code: "invalid_call_spec", path: ["participants", "intake", "prompt"], reason: "is required" } }, "Couldn't save: Agent intake › Prompt is required");
export const BackendUnmappedError: Story = actionStory({ status: 422, error: { code: "invalid_call_spec", path: ["future_field"], reason: "This field is not supported." } }, "Couldn't save: This field is not supported.");
export const NotPublishable: Story = actionStory({ status: 409, error: { code: "call_spec_not_publishable", path: ["participants", "intake", "prompt"], reason: "requires a supported configuration" } }, "Couldn't publish: Agent intake › Prompt requires a supported configuration", "Publish");
export const MissingCredential: Story = actionStory({ status: 422, error: { code: "provider_credential_unavailable", path: ["defaults", "capabilities", "model_inference"] } }, "No usable google credential for this tenant");
export const ProviderForbidden: Story = actionStory({ status: 403, error: { code: "provider_service_forbidden", path: ["defaults", "capabilities", "model_inference"] } }, "This tenant can't use google");
export const MissingCallerId: Story = actionStory({ status: 422, error: { code: "telephony_caller_id_missing", path: ["participants", "caller", "connection"] } }, "office-phone has no outbound caller ID number", "Save as draft", "outgoing");
export const InvalidPhoneRoute: Story = actionStory({ status: 422, error: { code: "invalid_telephony_route", path: ["participants", "caller", "connection"] } }, "The phone number isn't routable through office-phone", "Save as draft", "outgoing");
export const PrivateMaterial: Story = actionStory({ status: 422, error: { code: "private_call_spec_material", path: ["defaults", "capabilities", "model_inference", "provider_options"] } }, "Remove credentials or secrets from Call settings › Model inference");
export const RevisionConflict: Story = actionStory({ status: 409, error: { code: "revision_conflict" } }, "This spec changed while saving. Reload to see the latest revision");
export const NotFound: Story = actionStory({ status: 404, error: { code: "call_spec_not_found" } }, "This call spec no longer exists");
export const AuthoringForbidden: Story = actionStory({ status: 403, error: { code: "authoring_forbidden" } }, "You don't have permission to change call specs");
export const SessionExpired: Story = actionStory({ status: 401 }, "Your session expired. Changes in this tab are kept until you leave the page");
export const InvalidRequest: Story = actionStory({ status: 400, error: { code: "invalid_request" } }, "Couldn't save: the editor sent an invalid request");
export const Unavailable: Story = actionStory({ status: 503, error: { code: "call_spec_authoring_unavailable" } }, "Couldn't save. Try again");
export const NetworkFailure: Story = actionStory({}, "Couldn't save. Try again");
export const PublishedRevision: Story = { args: { scenario: "published" } };
export const OutgoingCall: Story = { args: { scenario: "outgoing" } };
export const HistoricalRevision: Story = { args: { scenario: "historical" }, play: async ({ canvasElement }) => {
  const canvas = within(canvasElement);
  await expect(canvas.getByText("Viewing revision 1. This saved revision is read-only.")).toBeVisible();
  await expect(canvas.getByRole("button", { name: "Publish" })).toBeDisabled();
} };
export const NarrowViewport: Story = { globals: { viewport: { value: "mobile1", isRotated: false } } };
export const LargeIntegers: Story = { args: { scenario: "large-integers" } };
export const LongContent: Story = { args: { scenario: "long" } };
export const AddParticipant: Story = { play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body); await userEvent.click(body.getByRole("button", { name: "Add agent" }));
  await expect(body.getByRole("textbox", { name: "Participant key" })).toHaveValue("agent");
} };
export const RenameParticipant: Story = { play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body); await userEvent.click(body.getByRole("button", { name: "Add agent" }));
  const key = body.getByRole("textbox", { name: "Participant key" }); await userEvent.clear(key); await userEvent.type(key, "assistant"); await userEvent.tab();
  await expect(body.getByRole("textbox", { name: "Participant key" })).toHaveValue("assistant");
} };
export const DrawTransfer: Story = { play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body); await userEvent.click(body.getByRole("button", { name: "Add agent" }));
  const close = body.queryByRole("button", { name: "Close" });
  if (close) { await userEvent.click(close); await waitFor(() => expect(body.queryByRole("dialog")).not.toBeInTheDocument()); }
  await userEvent.click(body.getByLabelText("Transfer from intake")); await userEvent.click(body.getByLabelText("Transfer to agent"));
  await userEvent.click(body.getByRole("button", { name: "More actions" }));
  await userEvent.click(body.getByRole("menuitem", { name: "JSON editor" }));
  await waitFor(() => {
    const source = JSON.parse((body.getByRole("textbox", { name: "Call spec JSON" }) as HTMLTextAreaElement).value);
    expect(source.participants.intake.transfers).toContain("agent");
  });
} };
export const ShowBackendField: Story = { ...BackendFieldError, play: async (context) => {
  await BackendFieldError.play?.(context);
  const body = within(context.canvasElement.ownerDocument.body); await userEvent.click(body.getByRole("button", { name: "Show" }));
  await waitFor(() => expect(body.getByRole("textbox", { name: "Prompt" })).toHaveFocus());
} };
export const IssuesList: Story = { args: { scenario: "invalid" }, play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body); await userEvent.click(body.getByRole("button", { name: "2 issues" }));
  await expect(body.getByRole("dialog", { name: "Call spec issues" })).toBeVisible();
} };

export const InvalidAgentReplyConfiguration: Story = actionStory({ status: 422, error: {
  code: "unsupported_call_plan", path: ["participants", "intake", "capabilities", "model_inference", "model"],
  reason: "The agent reply configuration could not be validated. Review the highlighted settings.",
} }, "Couldn't save: Agent intake › Model inference The agent reply configuration could not be validated. Review the highlighted settings.");
