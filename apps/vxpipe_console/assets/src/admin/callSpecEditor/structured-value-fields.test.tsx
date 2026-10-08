import { useState } from "react";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { ObjectFields } from "./structured-value-fields";
import type { JsonObject } from "./types";
afterEach(cleanup);
function Harness({ initial, disabled = false }: { initial?: JsonObject; disabled?: boolean }) {
  const [value, onChange] = useState(initial);
  return <><ObjectFields label="Options" path={["options"]} value={value} onChange={onChange} disabled={disabled} /><output data-testid="value">{JSON.stringify(value ?? null)}</output></>;
}
const saved = () => JSON.parse(screen.getByTestId("value").textContent!);
async function choose(label: string, value: string) {
  fireEvent.keyDown(screen.getByRole("combobox", { name: label }), { key: "ArrowDown" });
  fireEvent.click(await screen.findByRole("option", { name: value }));
}
test("typed nested edits preserve other JSON values without a raw JSON input", async () => {
  render(<Harness initial={{ voice: "custom", nested: { count: 4, enabled: true, values: [null, "keep"] } }} />);
  fireEvent.change(screen.getByRole("spinbutton", { name: "Options / nested / count" }), { target: { value: "7" } });
  await choose("Options / nested / enabled", "False");
  await choose("Options / nested / values / 1 type", "Number");
  expect(saved()).toEqual({ voice: "custom", nested: { count: 7, enabled: false, values: [0, "keep"] } });
  expect(screen.queryByRole("textbox", { name: /JSON/ })).not.toBeInTheDocument();
});
test("object keys can be renamed safely and collisions report an error without dropping data", () => {
  render(<Harness initial={{ first: "one", second: "two" }} />);
  const key = screen.getByRole("textbox", { name: "Options / first key" });
  fireEvent.change(key, { target: { value: "second" } }); fireEvent.blur(key);
  expect(screen.getByRole("alert")).toHaveTextContent("already exists");
  expect(saved()).toEqual({ first: "one", second: "two" });
  fireEvent.change(key, { target: { value: "__proto__" } }); fireEvent.blur(key);
  expect(Object.hasOwn(saved(), "__proto__")).toBe(true);
  expect(saved().__proto__).toBe("one");
  expect(saved().second).toBe("two");
});
test("adding, removing and clearing distinguish an omitted object from an explicit empty object", async () => {
  render(<Harness />);
  expect(saved()).toBeNull();
  fireEvent.click(screen.getByRole("button", { name: "Add Options field" }));
  expect(saved()).toEqual({ option_1: "" });
  await choose("Options / option_1 type", "Array");
  fireEvent.click(screen.getByRole("button", { name: "Add Options / option_1 item" }));
  expect(saved()).toEqual({ option_1: [""] });
  fireEvent.click(screen.getByRole("button", { name: "Remove Options / option_1" }));
  expect(saved()).toEqual({});
  fireEvent.click(screen.getByRole("button", { name: "Clear Options" }));
  expect(saved()).toBeNull();
});
test("read-only nested controls cannot mutate options", () => {
  render(<Harness initial={{ nested: { enabled: true, name: "kept" } }} disabled />);
  for (const role of ["textbox", "combobox", "button"] as const) for (const control of screen.getAllByRole(role)) expect(control).toBeDisabled();
  expect(saved()).toEqual({ nested: { enabled: true, name: "kept" } });
});
