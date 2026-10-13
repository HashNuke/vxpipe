import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { afterEach, expect, test } from "vitest";
import { PermissionEditor } from "./PermissionEditor";
import type { Grant } from "./types";
afterEach(cleanup);
function Editor() {
  const [value, setValue] = useState<Grant[]>([]);
  return <PermissionEditor value={value} onChange={setValue} />;
}
test("write selection includes read and removing read also removes write", () => {
  render(<Editor />);
  fireEvent.click(screen.getByRole("checkbox", { name: "Write Calls" }));
  expect(screen.getByRole("checkbox", { name: "Read Calls" })).toBeChecked();
  expect(screen.getByRole("checkbox", { name: "Write Calls" })).toBeChecked();
  fireEvent.click(screen.getByRole("checkbox", { name: "Read Calls" }));
  expect(
    screen.getByRole("checkbox", { name: "Write Calls" }),
  ).not.toBeChecked();
  expect(
    screen.queryByRole("checkbox", { name: /Write User/ }),
  ).not.toBeInTheDocument();
});
