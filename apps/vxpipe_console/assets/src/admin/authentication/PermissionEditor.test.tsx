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
function MixedEditor() {
  const [value, setValue] = useState<Grant[]>([
    { permission: "calls.read", scope: "all_tenants" },
    { permission: "calls.write", scope: "assigned_tenants" },
  ]);
  return <PermissionEditor value={value} onChange={setValue} />;
}
function ObservedMixedEditor({ seen }: { seen: Grant[][] }) {
  const value: Grant[] = [
    { permission: "calls.read", scope: "all_tenants" },
    { permission: "calls.write", scope: "assigned_tenants" },
  ];
  return (
    <PermissionEditor
      value={value}
      onChange={(next) => {
        seen.push(next);
      }}
    />
  );
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
test("mixed read/write scopes stay independent", () => {
  render(<MixedEditor />);
  const readScope = screen.getByRole("combobox", { name: "Read scope for Calls" });
  const writeScope = screen.getByRole("combobox", { name: "Write scope for Calls" });
  expect(readScope).toHaveValue("all_tenants");
  expect(writeScope).toHaveValue("assigned_tenants");
  fireEvent.change(writeScope, { target: { value: "all_tenants" } });
  // Both scopes remain independently editable after converging.
  expect(screen.getByRole("combobox", { name: "Read scope for Calls" })).toHaveValue("all_tenants");
  expect(screen.getByRole("checkbox", { name: "Read Calls" })).toBeChecked();
  expect(screen.getByRole("checkbox", { name: "Write Calls" })).toBeChecked();
});
test("changing one mixed scope leaves the other grant untouched", () => {
  const seen: Grant[][] = [];
  render(<ObservedMixedEditor seen={seen} />);
  fireEvent.change(screen.getByRole("combobox", { name: "Write scope for Calls" }), {
    target: { value: "all_tenants" },
  });
  expect(seen.at(-1)).toEqual([
    { permission: "calls.read", scope: "all_tenants" },
    { permission: "calls.write", scope: "all_tenants" },
  ]);
  cleanup();
  const seenRead: Grant[][] = [];
  render(<ObservedMixedEditor seen={seenRead} />);
  fireEvent.change(screen.getByRole("combobox", { name: "Read scope for Calls" }), {
    target: { value: "assigned_tenants" },
  });
  expect(seenRead.at(-1)).toEqual([
    { permission: "calls.read", scope: "assigned_tenants" },
    { permission: "calls.write", scope: "assigned_tenants" },
  ]);
});

test("platform service read replaces the separate authoring checkbox", () => {
  function ModifierEditor() {
    const [value, setValue] = useState<Grant[]>([]);
    return <>
      <PermissionEditor value={value} onChange={setValue} />
      <output data-testid="grants">{JSON.stringify(value)}</output>
    </>;
  }

  render(<ModifierEditor />);
  fireEvent.click(screen.getByRole("checkbox", { name: "Write Call specs" }));
  expect(screen.queryByRole("checkbox", { name: "Allow platform services in call specs" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("checkbox", { name: "Read Platform services" }));
  expect(screen.getByTestId("grants")).toHaveTextContent('"permission":"platform_services.read","scope":"installation"');
  fireEvent.change(screen.getByRole("combobox", { name: "Read scope for Call specs" }), {
    target: { value: "all_tenants" },
  });
  expect(screen.getByTestId("grants")).toHaveTextContent('"permission":"platform_services.read","scope":"installation"');
});

test("a new role can grant all-tenant read and assigned-tenant write", () => {
  render(<Editor />);
  fireEvent.click(screen.getByRole("checkbox", { name: "Write Calls" }));
  fireEvent.change(screen.getByRole("combobox", { name: "Read scope for Calls" }), {
    target: { value: "all_tenants" },
  });
  expect(screen.getByRole("combobox", { name: "Read scope for Calls" })).toHaveValue("all_tenants");
  expect(screen.getByRole("combobox", { name: "Write scope for Calls" })).toHaveValue("assigned_tenants");
});


test("provider credential writes use Services read", () => {
  render(<Editor />);
  expect(screen.queryByRole("checkbox", { name: "Read Provider credentials" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("checkbox", { name: "Write Provider credentials" }));
  expect(screen.getByRole("checkbox", { name: "Read Tenant services" })).toBeChecked();
  fireEvent.click(screen.getByRole("checkbox", { name: "Read Tenant services" }));
  expect(screen.getByRole("checkbox", { name: "Write Provider credentials" })).not.toBeChecked();
});

test("provider credential write scope keeps its Services read prerequisite broad enough", () => {
  render(<Editor />);
  fireEvent.click(screen.getByRole("checkbox", { name: "Write Provider credentials" }));
  fireEvent.change(screen.getByRole("combobox", { name: "Write scope for Provider credentials" }), { target: { value: "all_tenants" } });
  expect(screen.getByRole("combobox", { name: "Read scope for Tenant services" })).toHaveValue("all_tenants");
  fireEvent.change(screen.getByRole("combobox", { name: "Read scope for Tenant services" }), { target: { value: "assigned_tenants" } });
  expect(screen.getByRole("combobox", { name: "Write scope for Provider credentials" })).toHaveValue("assigned_tenants");
});
