import { cleanup, fireEvent, render } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { EditorTheme } from "./callSpecEditor/EditorTheme";

afterEach(cleanup);

test("pointer focus stays quiet across restored focus; keyboard navigation restores focus indicators", () => {
  const view = render(<EditorTheme><button>Action</button></EditorTheme>);
  fireEvent.pointerDown(document.body);
  expect(document.documentElement).toHaveAttribute("data-admin-input", "pointer");
  fireEvent.focus(document.querySelector("button")!);
  expect(document.documentElement).toHaveAttribute("data-admin-input", "pointer");
  fireEvent.keyDown(document.body, { key: "Tab" });
  expect(document.documentElement).toHaveAttribute("data-admin-input", "keyboard");
  fireEvent.pointerDown(document.body);
  fireEvent.keyDown(document.body, { key: "Shift" });
  expect(document.documentElement).toHaveAttribute("data-admin-input", "pointer");
  view.unmount();
  expect(document.documentElement).not.toHaveAttribute("data-admin-input");
});
