import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { FlowEditorHeader, FlowNameDialog } from "./editor-header";
import { FlowEditorToolbar } from "./editor-toolbar";

afterEach(cleanup);

const callbacks = () => ({ onEditFlowName: vi.fn(), onSaveDraft: vi.fn(), onPublish: vi.fn(), onShowIssues: vi.fn() });

test("publish and its menu are grouped; Save as draft is revealed and saves an unsaved spec", () => {
  const actions = callbacks();
  render(<FlowEditorHeader backHref="/specs" dirty {...actions} />);
  const group = within(screen.getByRole("group", { name: "Publish actions" }));
  expect(group.getByRole("button", { name: "Publish" })).toBeDisabled();
  expect(screen.queryByRole("menuitem", { name: "Save as draft" })).not.toBeInTheDocument();
  const trigger = group.getByRole("button", { name: "More actions" });
  expect(trigger).toBeEnabled();
  fireEvent.keyDown(trigger, { key: "ArrowDown" });
  fireEvent.click(screen.getByRole("menuitem", { name: "Save as draft" }));
  expect(actions.onSaveDraft).toHaveBeenCalledOnce();
  expect(actions.onPublish).not.toHaveBeenCalled();
  expect(screen.queryByRole("menu")).not.toBeInTheDocument();
});

test("header exposes revision, published state and actionable validation without blocking Save", () => {
  const actions = callbacks();
  render(<FlowEditorHeader backHref="/specs" flowName="Reception" revision={3} publishedRevision={2} issueCount={2} dirty {...actions} />);
  expect(screen.getByText("v3")).toHaveAttribute("title", "Revision 3");
  expect(screen.getByText("Published: 2")).toBeInTheDocument();
  expect(screen.getByText("Unsaved changes")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "2 issues" }));
  expect(actions.onShowIssues).toHaveBeenCalledOnce();
  fireEvent.keyDown(screen.getByRole("button", { name: "More actions" }), { key: "ArrowDown" });
  fireEvent.click(screen.getByRole("menuitem", { name: "Save as draft" }));
  expect(actions.onSaveDraft).toHaveBeenCalledOnce();
  expect(screen.queryByRole("button", { name: /test call|testchat/i })).not.toBeInTheDocument();
});

test.each(["saving", "publishing", "loading", "readOnly"] as const)("%s prevents mutations", (state) => {
  render(<FlowEditorHeader backHref="/specs" flowName="Reception" {...callbacks()} {...{ [state]: true }} />);
  expect(screen.getByRole("button", { name: "More actions" })).toBeDisabled();
  expect(screen.getByRole("button", { name: /^Publish|Saving/ })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Edit call spec name" })).toBeDisabled();
});

test("name dialog edits and submits the name with an accessible label", () => {
  const change = vi.fn();
  const submit = vi.fn((event) => event.preventDefault());
  render(<FlowNameDialog open value="Reception" onValueChange={change} onCancel={vi.fn()} onSubmit={submit} />);
  fireEvent.change(screen.getByRole("textbox", { name: "Call spec name" }), { target: { value: "Support" } });
  expect(change).toHaveBeenCalledWith("Support");
  fireEvent.click(screen.getByRole("button", { name: "Save name" }));
  expect(submit).toHaveBeenCalledOnce();
});

test("toolbar adds participants and exposes icon actions for arranging and Call settings", () => {
  const add = vi.fn();
  const arrange = vi.fn();
  const settings = vi.fn();
  const { rerender } = render(<FlowEditorToolbar onAddNode={add} onArrangeNodes={arrange} onOpenCallSettings={settings} />);
  fireEvent.click(screen.getByRole("button", { name: "Add agent" }));
  fireEvent.click(screen.getByRole("button", { name: "Add human" }));
  fireEvent.click(screen.getByRole("button", { name: "Arrange nodes" }));
  fireEvent.click(screen.getByRole("button", { name: "Call settings" }));
  expect(screen.getByRole("button", { name: "Arrange nodes" })).not.toHaveTextContent("Arrange");
  expect(screen.getByRole("button", { name: "Call settings" })).not.toHaveTextContent("Call settings");
  expect(add.mock.calls).toEqual([["agent"], ["human"]]);
  expect(arrange).toHaveBeenCalledOnce();
  expect(settings).toHaveBeenCalledOnce();
  rerender(<FlowEditorToolbar onAddNode={add} onArrangeNodes={arrange} onOpenCallSettings={settings} readOnly />);
  expect(screen.getByRole("button", { name: "Add agent" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Add human" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Arrange nodes" })).toBeEnabled();
  expect(screen.getByRole("button", { name: "Call settings" })).toBeEnabled();
});

test.each([{}, { readOnly: true }, { saveDisabled: true }, { authoringDisabled: true }])("JSON editor opens from the menu even when saving is unavailable: %j", (state: { readOnly?: boolean; saveDisabled?: boolean; authoringDisabled?: boolean }) => {
  const source = vi.fn();
  render(<FlowEditorHeader backHref="/specs" {...state} onShowSource={source} {...callbacks()} />);
  expect(screen.queryByRole("button", { name: "JSON" })).not.toBeInTheDocument();
  fireEvent.keyDown(screen.getByRole("button", { name: "More actions" }), { key: "ArrowDown" });
  const menu = within(screen.getByRole("menu"));
  if (state.readOnly || state.saveDisabled || state.authoringDisabled) {
    expect(menu.getByRole("menuitem", { name: "Save as draft" })).toHaveAttribute("aria-disabled", "true");
  }
  fireEvent.click(menu.getByRole("menuitem", { name: "JSON editor" }));
  expect(source).toHaveBeenCalledOnce();
});
test.each([{ revision: undefined }, { revision: 3, dirty: true }, { revision: 3, issueCount: 1 }])("publish requires a saved unchanged revision with no client issues: %j", (state) => {
  render(<FlowEditorHeader backHref="/specs" {...state} {...callbacks()} />);
  expect(screen.getByRole("button", { name: "Publish" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "More actions" })).toBeEnabled();
});
test("an unchanged saved revision can be published; missing and forbidden outcomes have separate gates", () => {
  const { rerender } = render(<FlowEditorHeader backHref="/specs" revision={3} {...callbacks()} />);
  expect(screen.getByRole("button", { name: "Publish" })).toBeEnabled();
  rerender(<FlowEditorHeader backHref="/specs" revision={3} saveDisabled {...callbacks()} />);
  expect(screen.getByRole("button", { name: "More actions" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Publish" })).toBeEnabled();
  rerender(<FlowEditorHeader backHref="/specs" revision={3} authoringDisabled {...callbacks()} />);
  expect(screen.getByRole("button", { name: "More actions" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Publish" })).toBeDisabled();
});
