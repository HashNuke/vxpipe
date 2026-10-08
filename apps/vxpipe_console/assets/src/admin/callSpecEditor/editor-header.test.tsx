import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { FlowEditorHeader, FlowNameDialog } from "./editor-header";
import { FlowEditorToolbar } from "./editor-toolbar";

afterEach(cleanup);

const callbacks = () => ({ onEditFlowName: vi.fn(), onSaveDraft: vi.fn(), onPublish: vi.fn(), onShowIssues: vi.fn() });

test("header exposes revision, published state and actionable validation without blocking Save", () => {
  const actions = callbacks();
  render(<FlowEditorHeader backHref="/specs" flowName="Reception" revision={3} publishedRevision={2} issueCount={2} dirty {...actions} />);
  expect(screen.getByText("Revision 3")).toBeInTheDocument();
  expect(screen.getByText("Published: 2")).toBeInTheDocument();
  expect(screen.getByText("Unsaved changes")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "2 issues" }));
  expect(actions.onShowIssues).toHaveBeenCalledOnce();
  fireEvent.click(screen.getByRole("button", { name: "Save draft" }));
  expect(actions.onSaveDraft).toHaveBeenCalledOnce();
  expect(screen.queryByRole("button", { name: /test call|testchat/i })).not.toBeInTheDocument();
});

test.each(["saving", "publishing", "loading", "readOnly"] as const)("%s prevents mutations", (state) => {
  render(<FlowEditorHeader backHref="/specs" flowName="Reception" {...callbacks()} {...{ [state]: true }} />);
  expect(screen.getByRole("button", { name: /Save draft|Saving/ })).toBeDisabled();
  expect(screen.getByRole("button", { name: /^Publish/ })).toBeDisabled();
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

test("toolbar offers only supported participant types and arranging", () => {
  const add = vi.fn();
  const arrange = vi.fn();
  const { rerender } = render(<FlowEditorToolbar onAddNode={add} onArrangeNodes={arrange} />);
  fireEvent.click(screen.getByRole("button", { name: "Add agent" }));
  fireEvent.click(screen.getByRole("button", { name: "Add human" }));
  fireEvent.click(screen.getByRole("button", { name: "Arrange nodes" }));
  expect(add.mock.calls).toEqual([["agent"], ["human"]]);
  expect(arrange).toHaveBeenCalledOnce();
  rerender(<FlowEditorToolbar onAddNode={add} onArrangeNodes={arrange} readOnly />);
  expect(screen.getByRole("button", { name: "Add agent" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Add human" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Arrange nodes" })).toBeEnabled();
});

test("source inspection remains available for read-only specs", () => {
  const source = vi.fn();
  render(<FlowEditorHeader backHref="/specs" readOnly onShowSource={source} {...callbacks()} />);
  fireEvent.click(screen.getByRole("button", { name: "View JSON" }));
  expect(source).toHaveBeenCalledOnce();
});
test.each([{ revision: undefined }, { revision: 3, dirty: true }, { revision: 3, issueCount: 1 }])("publish requires a saved unchanged revision with no client issues: %j", (state) => {
  render(<FlowEditorHeader backHref="/specs" {...state} {...callbacks()} />);
  expect(screen.getByRole("button", { name: "Publish" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Save draft" })).toBeEnabled();
});
test("an unchanged saved revision can be published; missing and forbidden outcomes have separate gates", () => {
  const { rerender } = render(<FlowEditorHeader backHref="/specs" revision={3} {...callbacks()} />);
  expect(screen.getByRole("button", { name: "Publish" })).toBeEnabled();
  rerender(<FlowEditorHeader backHref="/specs" revision={3} saveDisabled {...callbacks()} />);
  expect(screen.getByRole("button", { name: "Save draft" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Publish" })).toBeEnabled();
  rerender(<FlowEditorHeader backHref="/specs" revision={3} authoringDisabled {...callbacks()} />);
  expect(screen.getByRole("button", { name: "Save draft" })).toBeDisabled();
  expect(screen.getByRole("button", { name: "Publish" })).toBeDisabled();
});
