import { useState } from "react";
import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, userEvent, waitFor, within } from "storybook/test";
import { Button } from "../components/ui/button";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { EditorPageState } from "./editor-page-state";
import type { EditorResult } from "./editor-state";
import { EditorTheme } from "./EditorTheme";
import { CallSpecEditor } from "./flow-editor";
import { pageSnapshot, type EditorScenario } from "./page-fixtures";
import "../admin.css";

type Props = { theme: "dark" | "light"; scenario: EditorScenario; outcome?: EditorResult; pageStatus?: "loading" | "spec-error" | "catalog-error" };
// Adapted from Callpipe's flow_editor.stories: whole-page fixtures and real UI actions.
function FlowEditorStory({ theme, scenario, outcome, pageStatus }: Props) {
  const [destination, setDestination] = useState<string>();
  const [retried, setRetried] = useState(false);
  const [revision, setRevision] = useState(() => pageSnapshot(scenario).saved?.revision ?? 0);
  const snapshot = pageSnapshot(scenario);
  return <EditorTheme theme={theme}>{destination ? <main className="grid min-h-dvh place-content-center gap-4 bg-background p-6">
    <h1 className="text-lg font-semibold">{destination === "#services" ? "Tenant services" : "Call specs"}</h1>
    <p className="text-sm text-muted-foreground">Navigation confirmed. Return to the editor to continue the prototype.</p>
    <Button variant="outline" onClick={() => setDestination(undefined)}>Return to editor</Button>
  </main> : pageStatus && !retried ? <EditorPageState status={pageStatus === "loading" ? "loading" : "error"} resource={pageStatus === "catalog-error" ? "catalog" : "spec"} backHref="#call-specs" onRetry={() => setRetried(true)} />
    : <CallSpecEditor key={scenario} snapshot={snapshot} catalog={modelCatalogFixture} lookups={{ telephonyServices: [{ key: "office-phone", name: "Office phone" }], credentialNames: { google: ["primary"] }, mcpIntegrations: ["calendar"] }}
      backHref="#call-specs" servicesHref="#services" onNavigate={setDestination} onReload={async () => ({ ...pageSnapshot("default"), saved: { callSpecId: "appointments", revision: revision + 1, publishedRevision: null } })}
      execute={async (request) => {
        if (outcome) return outcome;
        if (request.action === "publish") return { status: 200, revision: request.revision };
        const next = revision + 1; setRevision(next);
        return { status: 201, revision: next, callSpecId: "appointments" };
      }} />}</EditorTheme>;
}
const meta = { title: "Vxpipe/Console/Call spec editor/Page", component: FlowEditorStory, parameters: { layout: "fullscreen" }, args: { theme: "dark", scenario: "default" } } satisfies Meta<typeof FlowEditorStory>;
export default meta;
type Story = StoryObj<typeof meta>;

function actionStory(outcome: EditorResult, message: string, action: "Save draft" | "Publish" = "Save draft", scenario: EditorScenario = "default"): Story {
  return { args: { outcome, scenario }, play: async ({ canvasElement }) => {
    const body = within(canvasElement.ownerDocument.body); await userEvent.click(body.getByRole("button", { name: action }));
    await expect(body.findByText(message)).resolves.toBeVisible();
  } };
}
export const Default: Story = { play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body);
  await expect(body.getByRole("heading", { name: "New Patient Appointment Intake" })).toBeInTheDocument();
  await expect(body.getByRole("button", { name: "Save draft" })).toBeEnabled();
} };
export const Loading: Story = { args: { pageStatus: "loading" } };
export const LoadFailure: Story = { args: { pageStatus: "spec-error" } };
export const CatalogFailure: Story = { args: { pageStatus: "catalog-error" } };
export const NewSpec: Story = { args: { scenario: "new" } };
export const ClientValidationErrors: Story = { args: { scenario: "invalid" } };
export const SaveBlocked: Story = { args: { scenario: "invalid" }, play: async ({ canvasElement }) => {
  const body = within(canvasElement.ownerDocument.body); await userEvent.click(body.getByRole("button", { name: "Save draft" }));
  await expect(body.getByText("Fix 2 issues before saving")).toBeVisible();
} };
export const Saved: Story = actionStory({ status: 201, revision: 4 }, "Saved as revision 4");
export const Published: Story = actionStory({ status: 200, revision: 3 }, "Published revision 3", "Publish");
export const BackendFieldError: Story = actionStory({ status: 422, error: { code: "invalid_call_spec", path: ["participants", "intake", "prompt"], reason: "is required" } }, "Couldn't save: Agent intake › Prompt is required");
export const BackendUnmappedError: Story = actionStory({ status: 422, error: { code: "invalid_call_spec", path: ["future_field"], reason: "This field is not supported." } }, "Couldn't save: This field is not supported.");
export const NotPublishable: Story = actionStory({ status: 409, error: { code: "call_spec_not_publishable", path: ["participants", "intake", "prompt"], reason: "requires a supported configuration" } }, "Couldn't publish: Agent intake › Prompt requires a supported configuration", "Publish");
export const MissingCredential: Story = actionStory({ status: 422, error: { code: "provider_credential_unavailable", path: ["defaults", "capabilities", "model_inference"] } }, "No usable google credential for this tenant");
export const ProviderForbidden: Story = actionStory({ status: 403, error: { code: "provider_service_forbidden", path: ["defaults", "capabilities", "model_inference"] } }, "This tenant can't use google");
export const MissingCallerId: Story = actionStory({ status: 422, error: { code: "telephony_caller_id_missing", path: ["participants", "caller", "connection"] } }, "office-phone has no outbound caller ID number", "Save draft", "outgoing");
export const InvalidPhoneRoute: Story = actionStory({ status: 422, error: { code: "invalid_telephony_route", path: ["participants", "caller", "connection"] } }, "The phone number isn't routable through office-phone", "Save draft", "outgoing");
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
export const HistoricalSchema: Story = { args: { scenario: "historical" } };
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
  await userEvent.click(body.getByRole("button", { name: "View JSON" }));
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
