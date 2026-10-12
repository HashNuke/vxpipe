import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { modelCatalogFixture } from "../modelCatalogFixtures";
import { editorFixture } from "./editorFixtures";
import { CallSpecEditor } from "./flow-editor";
import type { FlowCanvasProps } from "./flow-canvas";
import { projectGraph } from "./graph";
import type { EditorResult, EditorSnapshot } from "./editor-state";
import type { ExecuteEditorRequest } from "./use-editor";

vi.mock("./flow-canvas", () => ({ FlowCanvas: (props: FlowCanvasProps) => <div>
  {projectGraph(props.document).nodes.map((node) => <button key={node.id} onClick={() => props.onSelectNode(node.id)}>Select {node.id}</button>)}
  {projectGraph(props.document).edges.map((edge) => <button key={edge.id} onClick={() => props.onSelectEdge(edge.id)}>Select {edge.id}</button>)}
  <button onClick={() => props.onConnect("intake", "agent")}>Connect intake to agent</button>
</div> }));
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
const snapshot: EditorSnapshot = { document: structuredClone(editorFixture), saved: { callSpecId: "appointments", revision: 3, publishedRevision: null } };
snapshot.document.source.defaults = { capabilities: { model_inference: { provider: "google", model: "gemini-2.5-flash" } } };
const properties = () => ({ snapshot, catalog: modelCatalogFixture, lookups: { telephonyServices: [], credentialNames: {}, mcpIntegrations: [] },
  backHref: "/specs", servicesHref: "/services", onNavigate: vi.fn(), onReload: vi.fn(async () => snapshot),
  execute: vi.fn<ExecuteEditorRequest>(async () => ({ status: 201, revision: 4 })) });
const click = (name: string) => fireEvent.click(screen.getByRole("button", { name }));
const saveDraft = () => {
  fireEvent.keyDown(screen.getByRole("button", { name: "More actions" }), { key: "ArrowDown" });
  fireEvent.click(screen.getByRole("menuitem", { name: "Save as draft" }));
};
const openJsonEditor = () => {
  fireEvent.keyDown(screen.getByRole("button", { name: "More actions" }), { key: "ArrowDown" });
  fireEvent.click(screen.getByRole("menuitem", { name: "JSON editor" }));
};
const expectDraftDisabled = () => {
  fireEvent.keyDown(screen.getByRole("button", { name: "More actions" }), { key: "ArrowDown" });
  expect(screen.getByRole("menuitem", { name: "Save as draft" })).toHaveAttribute("aria-disabled", "true");
  fireEvent.keyDown(screen.getByRole("menu"), { key: "Escape" });
};
const fill = (name: string, value: string) => fireEvent.change(screen.getByRole("textbox", { name }), { target: { value } });
const rename = (value: string) => {
  click("Edit call spec name");
  fireEvent.change(within(screen.getByRole("dialog", { name: "Edit call spec name" })).getByRole("textbox", { name: "Call spec name" }), { target: { value } });
  click("Save name");
};

test("new agents require a user-written prompt before saving", async () => {
  const props = properties();
  render(<CallSpecEditor {...props} />);
  click("Add agent");
  expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveValue("");
  saveDraft();
  expect(props.execute).not.toHaveBeenCalled();
  expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveAttribute("aria-invalid", "true");
  fill("Prompt", "   "); saveDraft();
  expect(props.execute).not.toHaveBeenCalled();
  fill("Prompt", "Help customers change their appointment."); saveDraft();
  await waitFor(() => expect(props.execute).toHaveBeenCalledOnce());
  expect(props.execute).toHaveBeenCalledWith(expect.objectContaining({ source: expect.objectContaining({
    participants: expect.objectContaining({ agent: expect.objectContaining({ prompt: "Help customers change their appointment." }) }),
  }) }), expect.any(AbortSignal));
});

test("source edits save exactly, update revision badges and publish the saved revision", async () => {
  const props = properties(); render(<CallSpecEditor {...props} />);
  rename("Renamed call");
  expect(screen.getByRole("button", { name: "Edit call spec name" })).toHaveTextContent("Renamed call");
  expect(screen.getByRole("button", { name: "Publish" })).toBeDisabled();
  saveDraft();
  expect(await screen.findByText("Saved as revision 4")).toBeVisible();
  expect(props.execute).toHaveBeenCalledWith(expect.objectContaining({ action: "save", source: { ...snapshot.document.source, name: "Renamed call" } }), expect.any(AbortSignal));
  props.execute.mockResolvedValue({ status: 200, revision: 4 });
  click("Publish");
  expect(await screen.findByText("Published revision 4")).toBeVisible();
  expect(screen.getByText("Published: 4")).toBeVisible();
  expect(screen.queryByText("Unsaved changes")).not.toBeInTheDocument();
});

test("name issues open the header rename dialog with the error and can be corrected", async () => {
  const props = properties();
  props.execute.mockResolvedValueOnce({ status: 422, error: { code: "invalid_call_spec", path: ["name"], reason: "Choose a different name" } });
  render(<CallSpecEditor {...props} />); saveDraft();
  await screen.findByText("Couldn't save: Call spec name Choose a different name"); click("Show");
  const name = within(screen.getByRole("dialog", { name: "Edit call spec name" })).getByRole("textbox", { name: "Call spec name" });
  await waitFor(() => expect(name).toHaveFocus());
  expect(name).toHaveAccessibleDescription("Choose a different name");
  fireEvent.change(name, { target: { value: "Updated name" } }); click("Save name");
  expect(screen.getByRole("button", { name: "Edit call spec name" })).toHaveTextContent("Updated name");
  expect(screen.queryByText("Choose a different name")).not.toBeInTheDocument();
});

test("blocked save shows the first issue, selects its inspector and focuses the field", async () => {
  const props = properties(); render(<CallSpecEditor {...props} />);
  click("Select intake"); fill("Prompt", ""); click("Call settings"); saveDraft();
  expect(props.execute).not.toHaveBeenCalled();
  expect(screen.getByText("Fix 1 issue before saving")).toBeVisible();
  click("Show first issue");
  await waitFor(() => expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveFocus());
  click("1 issue");
  expect(screen.getByRole("dialog", { name: "Call spec issues" })).toBeVisible();
});

test("backend field errors survive unrelated edits and disappear when their field changes", async () => {
  const props = properties();
  props.execute.mockResolvedValue({ status: 422, error: { code: "invalid_call_spec", path: ["participants", "intake", "prompt"], reason: "needs a greeting" } });
  render(<CallSpecEditor {...props} />); saveDraft();
  await screen.findByText("Couldn't save: Agent intake › Prompt needs a greeting"); click("Show");
  expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveAttribute("aria-invalid", "true");
  rename("Renamed draft");
  expect(screen.getByText("needs a greeting")).toBeVisible();
  fill("Prompt", "Hello. How can I help?");
  expect(screen.queryByText("needs a greeting")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "1 issue" })).not.toBeInTheDocument();
});

test("retry uses current source and replaces the previous notification", async () => {
  const props = properties(); props.execute.mockRejectedValueOnce(new Error("offline"));
  render(<CallSpecEditor {...props} />); saveDraft();
  await screen.findByText("Couldn't save. Try again"); rename("Retry draft"); click("Retry");
  await screen.findByText("Saved as revision 4");
  expect(props.execute).toHaveBeenLastCalledWith(expect.objectContaining({ source: expect.objectContaining({ name: "Retry draft" }) }), expect.any(AbortSignal));
  expect(screen.getAllByLabelText("Notification")).toHaveLength(1);
});

test("back navigation retains edits until the operator confirms leaving", () => {
  const props = properties(); render(<CallSpecEditor {...props} />); rename("Keep me");
  fireEvent.click(screen.getByRole("link", { name: "Back to call specs" }));
  expect(props.onNavigate).not.toHaveBeenCalled();
  click("Keep editing"); expect(screen.getByRole("button", { name: "Edit call spec name" })).toHaveTextContent("Keep me");
  fireEvent.click(screen.getByRole("link", { name: "Back to call specs" })); click("Leave page");
  expect(props.onNavigate).toHaveBeenCalledWith("/specs");
});

test("conflict reload asks before discarding changes and replaces them only after success", async () => {
  const props = properties();
  props.execute.mockResolvedValue({ status: 409, error: { code: "revision_conflict" } });
  props.onReload.mockResolvedValue({ ...snapshot, saved: { ...snapshot.saved!, revision: 8 } });
  render(<CallSpecEditor {...props} />); rename("Unsaved draft"); saveDraft();
  await screen.findByText("This spec changed while saving. Reload to see the latest revision"); click("Reload");
  expect(props.onReload).not.toHaveBeenCalled();
  fireEvent.click(within(screen.getByRole("alertdialog")).getByRole("button", { name: "Reload latest revision" }));
  await screen.findByText("v8");
  expect(screen.getByRole("button", { name: "Edit call spec name" })).toHaveTextContent(snapshot.document.source.name!);
});

test.each([{ width: 1440, readOnly: false }, { width: 390, readOnly: false }, { width: 1440, readOnly: true }])("a transfer edge opens its source's Transfers tab at $width px with readOnly=$readOnly", ({ width, readOnly }) => {
  vi.stubGlobal("innerWidth", width);
  const props = properties();
  render(<CallSpecEditor {...props} snapshot={{ ...snapshot, document: { ...snapshot.document, readOnly } }} />);
  if (width >= 1024) click("Select specialist");
  click("Select transfer:intake:specialist");
  const sidebar = within(screen.getByRole(width < 1024 ? "dialog" : "region", { name: "Participant intake" }));
  expect(sidebar.getByRole("textbox", { name: "Participant key" })).toHaveValue("intake");
  expect(sidebar.getByRole("tab", { name: "Transfers" })).toHaveAttribute("data-state", "active");
  expect(sidebar.getByRole("button", { name: "Remove transfer to specialist" })).toHaveProperty("disabled", readOnly);
  expect(sidebar.queryByText("Source", { exact: true })).not.toBeInTheDocument();
  expect(sidebar.queryByText("Target", { exact: true })).not.toBeInTheDocument();
  expect(sidebar.queryByRole("button", { name: "Delete transfer" })).not.toBeInTheDocument();
  expect(screen.queryByText("Unsaved changes")).not.toBeInTheDocument();
  expect(props.execute).not.toHaveBeenCalled();
});

test("after following an edge, tabs stay navigable and clicking the edge returns to Transfers", () => {
  render(<CallSpecEditor {...properties()} />);
  click("Select transfer:intake:specialist");
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Prompt" }), { button: 0 });
  expect(screen.getByRole("textbox", { name: "Prompt" })).toBeVisible();
  click("Select transfer:intake:specialist");
  expect(screen.getByRole("tab", { name: "Transfers" })).toHaveAttribute("data-state", "active");
});

test("the call entry edge opens Entry connection settings", () => {
  render(<CallSpecEditor {...properties()} />);
  click("Select $entry-edge");
  expect(screen.getByRole("region", { name: "Entry settings" })).toBeVisible();
  expect(screen.getByRole("tab", { name: "Connection" })).toHaveAttribute("data-state", "active");
  expect(screen.queryByRole("button", { name: "Delete participant" })).not.toBeInTheDocument();
});

test("add, connect, rename and remove a transfer keep the portable source in sync", () => {
  render(<CallSpecEditor {...properties()} />); click("Add agent");
  expect(screen.getByRole("textbox", { name: "Participant key" })).toHaveValue("agent");
  click("Connect intake to agent"); click("Select agent"); fill("Participant key", "helper"); fireEvent.blur(screen.getByRole("textbox", { name: "Participant key" }));
  click("Select transfer:intake:helper"); click("Remove transfer to helper"); openJsonEditor();
  const source = JSON.parse((screen.getByRole("textbox", { name: "Call spec JSON" }) as HTMLTextAreaElement).value);
  expect(source.participants.helper.type).toBe("agent");
  expect(source.participants.intake.transfers).toEqual(["specialist"]);
  expect(source).not.toHaveProperty("nodes"); expect(source).not.toHaveProperty("edges");
});

test("failed rename keeps the field draft and reports one action failure", () => {
  render(<CallSpecEditor {...properties()} />); click("Select intake"); fill("Participant key", "caller");
  fireEvent.blur(screen.getByRole("textbox", { name: "Participant key" }));
  expect(screen.getByRole("textbox", { name: "Participant key" })).toHaveValue("caller");
  expect(screen.getByLabelText("Notification")).toHaveTextContent("Couldn't rename");
  expect(screen.getAllByLabelText("Notification")).toHaveLength(1);
});

test("adding a participant on a phone opens its inspector", () => {
  vi.stubGlobal("innerWidth", 390);
  render(<CallSpecEditor {...properties()} />); click("Add agent");
  expect(screen.getByRole("dialog", { name: "Participant agent" })).toBeVisible();
  expect(screen.getByRole("textbox", { name: "Participant key" })).toHaveValue("agent");
});

test("Open services uses the same unsaved-change guard", async () => {
  const props = properties(); props.execute.mockResolvedValue({ status: 422, error: { code: "provider_credential_unavailable", path: ["defaults", "capabilities", "model_inference"] } });
  render(<CallSpecEditor {...props} />); rename("Keep draft"); saveDraft();
  await screen.findAllByText("No usable google credential for this tenant"); click("Open services");
  expect(props.onNavigate).not.toHaveBeenCalled(); click("Leave page");
  expect(props.onNavigate).toHaveBeenCalledWith("/services");
});

test("a failed reload keeps the current draft and offers another reload", async () => {
  const props = properties(); props.execute.mockResolvedValue({ status: 409, error: { code: "revision_conflict" } });
  props.onReload.mockRejectedValue(new Error("offline"));
  render(<CallSpecEditor {...props} />); rename("Keep draft"); saveDraft();
  await screen.findByText("This spec changed while saving. Reload to see the latest revision"); click("Reload"); click("Reload latest revision");
  await screen.findByText("Couldn't reload. Your changes are still here.");
  expect(screen.getByRole("button", { name: "Edit call spec name" })).toHaveTextContent("Keep draft");
  expect(screen.getByText("v3")).toBeVisible();
  expect(screen.getByRole("button", { name: "Reload" })).toBeEnabled();
});

test("the browser unload guard clears after saving and is absent for historical viewing", async () => {
  const props = properties(); const view = render(<CallSpecEditor {...props} />);
  rename("New name");
  const dirty = new Event("beforeunload", { cancelable: true }); window.dispatchEvent(dirty); expect(dirty.defaultPrevented).toBe(true);
  saveDraft(); await screen.findByText("Saved as revision 4");
  const saved = new Event("beforeunload", { cancelable: true }); window.dispatchEvent(saved); expect(saved.defaultPrevented).toBe(false);
  view.unmount(); render(<CallSpecEditor {...properties()} snapshot={{ document: { ...snapshot.document, readOnly: true } }} />);
  const historical = new Event("beforeunload", { cancelable: true }); window.dispatchEvent(historical); expect(historical.defaultPrevented).toBe(false);
});

test("Show opens the phone inspector and focuses the requested field", async () => {
  vi.stubGlobal("innerWidth", 390);
  const initial = structuredClone(snapshot);
  if (initial.document.source.participants.intake?.type === "agent") initial.document.source.participants.intake.prompt = "";
  render(<CallSpecEditor {...properties()} snapshot={initial} />); saveDraft(); click("Show first issue");
  expect(screen.getByRole("dialog", { name: "Participant intake" })).toBeVisible();
  await waitFor(() => expect(screen.getByRole("textbox", { name: "Prompt" })).toHaveFocus());
});

test("an unmapped backend error opens the issues drawer through Show", async () => {
  const props = properties(); props.execute.mockResolvedValue({ status: 422, error: { code: "invalid_call_spec", path: ["new_field"], reason: "unsupported field" } });
  render(<CallSpecEditor {...props} />); saveDraft(); await screen.findByText("Couldn't save: unsupported field"); click("Show");
  const drawer = screen.getByRole("dialog", { name: "Call spec issues" });
  expect(within(drawer).getByText("unsupported field")).toBeVisible();
  fireEvent.click(within(drawer).getByRole("button", { name: "Show" }));
  expect(drawer).toBeVisible();
});

test("tool action failures keep the modal draft and use the editor notification", () => {
  render(<CallSpecEditor {...properties()} />); click("Select intake");
  fireEvent.mouseDown(screen.getByRole("tab", { name: "Tools" }), { button: 0 }); click("Add tool"); click("Host");
  fill("Tool name", "availability"); click("Next");
  fireEvent.click(within(screen.getByRole("dialog", { name: "Add tool" })).getByRole("button", { name: "Add tool" }));
  expect(screen.getByRole("dialog", { name: "Add tool" })).toBeVisible();
  expect(screen.getByRole("textbox", { name: "Local tool key" })).toHaveValue("availability");
  expect(screen.getByLabelText("Notification")).toHaveTextContent("Couldn't save this tool");
});

test("an old recovery action cannot reload while a new save is pending", async () => {
  const props = properties();
  props.execute.mockResolvedValueOnce({ status: 409, error: { code: "revision_conflict" } });
  let finish!: (result: EditorResult) => void;
  props.execute.mockImplementationOnce(() => new Promise((resolve) => { finish = resolve; }));
  render(<CallSpecEditor {...props} />); saveDraft();
  await screen.findByText("This spec changed while saving. Reload to see the latest revision");
  saveDraft();
  expect(screen.getByRole("button", { name: "Reload" })).toBeDisabled();
  expect(props.onReload).not.toHaveBeenCalled();
  await act(async () => finish({ status: 201, revision: 4 }));
});


test("call spec JSON applies to the draft and saves through the existing revision flow", async () => {
  const props = properties(); render(<CallSpecEditor {...props} />);
  openJsonEditor();
  const next = { ...snapshot.document.source, name: "Edited in JSON" };
  fill("Call spec JSON", JSON.stringify(next));
  expect(screen.getByRole("button", { name: "Publish" })).toBeDisabled();
  click("Apply JSON");
  expect(screen.getByRole("heading", { name: "Edited in JSON" })).toBeInTheDocument();
  click("Close"); saveDraft();
  await waitFor(() => expect(props.execute).toHaveBeenCalledWith(expect.objectContaining({ source: next }), expect.any(AbortSignal)));
});

test("unapplied participant JSON survives switching participants and guards departure", () => {
  const props = properties(); render(<CallSpecEditor {...props} />);
  click("Select intake"); click("Participant JSON");
  fill("Participant JSON", '{');
  click("Select specialist"); click("Select intake");
  expect(screen.getByRole("textbox", { name: "Participant JSON" })).toHaveValue('{');
  expectDraftDisabled();
  fireEvent.click(screen.getByRole("link", { name: "Back to call specs" }));
  expect(props.onNavigate).not.toHaveBeenCalled(); click("Keep editing");
  click("Discard JSON changes");
  expect(screen.getByRole("button", { name: "More actions" })).toBeEnabled();
});


test("Review JSON edits reopens a hidden participant draft", () => {
  render(<CallSpecEditor {...properties()} />); click("Select intake"); click("Participant JSON");
  fill("Participant JSON", '{'); click("Participant JSON");
  click("Review JSON edits");
  expect(screen.getByRole("textbox", { name: "Participant JSON" })).toHaveValue('{');
});

test("a removed participant's JSON draft remains reviewable and discardable", () => {
  render(<CallSpecEditor {...properties()} />); click("Select specialist"); click("Participant JSON");
  fill("Participant JSON", '{'); openJsonEditor();
  const next = structuredClone(snapshot.document.source);
  delete next.participants.specialist;
  if (next.participants.intake.type === "agent") delete next.participants.intake.transfers;
  fill("Call spec JSON", JSON.stringify(next)); fireEvent.click(within(screen.getByRole("dialog", { name: "Call spec source" })).getByRole("button", { name: "Apply JSON" })); click("Close");
  click("Review JSON edits");
  expect(screen.getByRole("textbox", { name: "Participant JSON" })).toHaveValue('{');
  click("Discard JSON changes");
  expect(screen.getByRole("button", { name: "More actions" })).toBeEnabled();
});

test("retrying a failed save waits for unapplied JSON edits", async () => {
  const props = properties(); props.execute.mockRejectedValueOnce(new Error("offline"));
  render(<CallSpecEditor {...props} />); saveDraft();
  await screen.findByText("Couldn't save. Try again");
  click("Select intake"); click("Participant JSON"); fill("Participant JSON", '{');
  click("Participant JSON"); click("Retry");
  expect(props.execute).toHaveBeenCalledTimes(1);
  expect(screen.getByRole("textbox", { name: "Participant JSON" })).toHaveValue('{');
});
