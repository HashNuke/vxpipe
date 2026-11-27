import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { ConversationLanguages } from "./conversation-languages";
import { editorFixture } from "./editorFixtures";
import { editSource } from "./editSource";
import { parseSource, serializeSource } from "./source";
import { validateSource } from "./validation";
import type { SourceDocument } from "./types";

afterEach(cleanup);

function documentWith(languages?: string[], readOnly = false): SourceDocument {
  const document = structuredClone(editorFixture);
  document.readOnly = readOnly;
  if (languages === undefined) delete document.source.conversation_languages;
  else document.source.conversation_languages = languages;
  return document;
}

test("Tagalog (tl) and Filipino (fil) are labelled distinctly with codes", () => {
  render(<ConversationLanguages document={documentWith(["tl", "fil"])} onChange={vi.fn()} />);
  expect(screen.getByText("Tagalog")).toBeInTheDocument();
  expect(screen.getByText("Filipino")).toBeInTheDocument();
  expect(screen.getByText("tl")).toBeInTheDocument();
  expect(screen.getByText("fil")).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /Remove Tagalog.*tl/ })).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /Remove Filipino.*fil/ })).toBeInTheDocument();
});

test("Mandarin (cmn-CN) and Chinese (zh-CN) are labelled distinctly with codes", () => {
  render(<ConversationLanguages document={documentWith(["cmn-CN", "zh-CN"])} onChange={vi.fn()} />);
  expect(screen.getByText("Mandarin (China)")).toBeInTheDocument();
  expect(screen.getByText("Chinese (China)")).toBeInTheDocument();
  expect(screen.getByText("cmn-CN")).toBeInTheDocument();
  expect(screen.getByText("zh-CN")).toBeInTheDocument();
});

test("options with scripts or regions show their codes for search and chips", () => {
  const change = vi.fn();
  render(<ConversationLanguages document={documentWith(["pa-Guru-IN", "sd-Arab-IN"])} onChange={change} />);
  expect(screen.getByText("pa-Guru-IN")).toBeInTheDocument();
  expect(screen.getByText("sd-Arab-IN")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("combobox", { name: "Conversation languages" }));
  expect(screen.getByRole("option", { name: /pa-Guru-IN/ })).toBeInTheDocument();
  expect(screen.getByRole("option", { name: /sd-Arab-IN/ })).toBeInTheDocument();
});

test("Automatic shows when omitted or empty and clearing returns to Automatic", () => {
  const change = vi.fn();
  const view = render(<ConversationLanguages document={documentWith(undefined)} onChange={change} />);
  expect(screen.getByText("Automatic")).toBeInTheDocument();
  view.unmount();
  cleanup();
  render(<ConversationLanguages document={documentWith(["en-GB", "es-MX"])} onChange={change} />);
  fireEvent.click(screen.getByRole("combobox", { name: "Conversation languages" }));
  fireEvent.click(screen.getByRole("option", { name: "Automatic" }));
  expect(change.mock.lastCall?.[0].source.conversation_languages).toEqual([]);
});

test("priority order is preserved on choose and remove", () => {
  const change = vi.fn();
  render(<ConversationLanguages document={documentWith(["en-GB", "es-MX"])} onChange={change} />);
  expect(screen.getByText("British English")).toBeInTheDocument();
  expect(screen.getByText("Mexican Spanish")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: /Remove British English/ }));
  expect(change.mock.lastCall?.[0].source.conversation_languages).toEqual(["es-MX"]);
  const reopened = editSource(documentWith(["es-MX"]), source => {
    source.conversation_languages = [...source.conversation_languages!, "fr-FR"];
  });
  expect(reopened.source.conversation_languages).toEqual(["es-MX", "fr-FR"]);
});

test("read-only documents disable the picker and removal", () => {
  render(<ConversationLanguages document={documentWith(["en"], true)} onChange={vi.fn()} />);
  expect(screen.getByRole("combobox", { name: "Conversation languages" })).toBeDisabled();
  expect(screen.getByRole("button", { name: /Remove English/ })).toBeDisabled();
  expect(() => editSource(documentWith(["en"], true), source => {
    source.conversation_languages = [];
  })).toThrow();
});

test("validation accepts Automatic and ordered tags but rejects unknown or duplicate codes", () => {
  const base = structuredClone(editorFixture.source);
  expect(validateSource({ ...base, conversation_languages: undefined }).filter(issue => issue.path[0] === "conversation_languages")).toEqual([]);
  expect(validateSource({ ...base, conversation_languages: [] }).filter(issue => issue.path[0] === "conversation_languages")).toEqual([]);
  expect(validateSource({ ...base, conversation_languages: ["en-GB", "es-MX"] }).filter(issue => issue.path[0] === "conversation_languages")).toEqual([]);
  expect(validateSource({ ...base, conversation_languages: ["xx-YY"] })).toContainEqual(
    expect.objectContaining({ path: ["conversation_languages"] }),
  );
  expect(validateSource({ ...base, conversation_languages: ["en", "en"] })).toContainEqual(
    expect.objectContaining({ path: ["conversation_languages"] }),
  );
});

test("save and reopen round-trip preserves language order and filters unknown tags for display", () => {
  const document = documentWith(["en-GB", "es-MX", "fr-FR"]);
  const json = serializeSource(document);
  const reopened = parseSource(json);
  expect(reopened.source.conversation_languages).toEqual(["en-GB", "es-MX", "fr-FR"]);
  expect(reopened.readOnly).toBe(false);
  render(<ConversationLanguages document={documentWith(["en-GB", "xx-YY"])} onChange={vi.fn()} />);
  expect(screen.getByText("British English")).toBeInTheDocument();
  expect(screen.queryByText("xx-YY")).not.toBeInTheDocument();
});

test("Enter on an exact language code selects that code before fuzzy name matches", () => {
  const change = vi.fn();
  render(<ConversationLanguages document={documentWith()} onChange={change} />);
  fireEvent.click(screen.getByRole("combobox", { name: "Conversation languages" }));
  const search = screen.getByRole("combobox", {name: "Search languages"});
  fireEvent.change(search, {target: {value: "es"}});
  fireEvent.keyDown(search, {key: "Enter"});
  expect(change.mock.lastCall?.[0].source.conversation_languages).toEqual(["es"]);
});
