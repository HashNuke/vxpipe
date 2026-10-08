import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { EditorTheme } from "./EditorTheme";

test("the editor shares its theme with body portals and restores the host on unmount", () => {
  document.body.setAttribute("data-admin-editor-theme", "host");
  const { rerender, unmount } = render(<EditorTheme theme="light"><p>Editor contents</p></EditorTheme>);
  expect(screen.getByText("Editor contents").closest(".vx-admin")).toHaveAttribute("data-theme", "light");
  expect(document.body).toHaveAttribute("data-admin-editor-theme", "light");
  rerender(<EditorTheme theme="dark"><p>Editor contents</p></EditorTheme>);
  expect(document.body).toHaveAttribute("data-admin-editor-theme", "dark");
  unmount();
  expect(document.body).toHaveAttribute("data-admin-editor-theme", "host");
  document.body.removeAttribute("data-admin-editor-theme");
});
