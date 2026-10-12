import { useState } from "react";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { ConnectionFields } from "./connection-fields";
import { editorFixture } from "./editorFixtures";
import type { PhoneNumberLoader } from "./inspectorTypes";
afterEach(cleanup);
function Harness({ configured = true, loader }: { configured?: boolean; loader?: PhoneNumberLoader }) {
  const [document, onChange] = useState(structuredClone(editorFixture));
  return <><ConnectionFields document={document} onChange={onChange} participantKey="caller" services={configured ? [{ key: "office", name: "Office", provider: "telnyx" }] : []} loadNumbers={loader} /><output>{JSON.stringify(document.source.participants.caller)}</output></>;
}
test("Phone opens a provider dialog without changing the connection; no services means cancel only", () => {
  render(<Harness configured={false} />);
  fireEvent.click(screen.getByRole("radio", { name: "Phone" }));
  expect(screen.getByRole("dialog", { name: "Phone connection" })).toBeInTheDocument();
  expect(screen.getByRole("combobox", { name: "Telephony service" })).toBeDisabled();
  expect(screen.queryByRole("radio", { name: "Twilio" })).not.toBeInTheDocument();
  expect(screen.getByText(/Set up at least one telephony service/)).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Assign number" })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
  expect(screen.getByRole("radio", { name: "Web" })).toBeChecked();
});
test("owned numbers are fetched, assigned numbers disabled, search and more pages call the server", async () => {
  const loader = vi.fn<PhoneNumberLoader>().mockResolvedValueOnce({ numbers: [
    { id: "1", number: "+15550000001", name: "Support", available: false, assignedTo: ["Published reception"] },
    { id: "2", number: "+15550000002", name: "Office", available: true, assignedTo: [] }
  ], nextPage: "2" }).mockResolvedValue({ numbers: [{ id: "3", number: "+15550000003", name: "New", available: true, assignedTo: [] }], nextPage: null });
  render(<Harness loader={loader} />);
  fireEvent.click(screen.getByRole("radio", { name: "Phone" }));
  expect(await screen.findByRole("radio", { name: /Support/ })).toBeDisabled();
  expect(screen.getByText("In use")).toBeInTheDocument();
  expect(screen.queryByText(/Published reception/)).not.toBeInTheDocument();
  expect(screen.getByRole("combobox", { name: "Telephony service" })).toHaveTextContent("Telnyx · Office");
  expect(screen.getByText("Choose a telephony service and a phone number.")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Load more" }));
  await screen.findByRole("radio", { name: /New/ });
  expect(loader.mock.calls[1]?.slice(0, 3)).toEqual(["office", "", "2"]);
  fireEvent.change(screen.getByRole("textbox", { name: "Search phone numbers" }), { target: { value: "555" } });
  fireEvent.click(screen.getByRole("button", { name: "Search" }));
  await waitFor(() => expect(loader.mock.calls.at(-1)?.slice(0, 3)).toEqual(["office", "555", null]));
  fireEvent.click(await screen.findByRole("radio", { name: /New/ }));
  fireEvent.click(screen.getByRole("button", { name: "Assign number" }));
  expect(screen.getByRole("status").textContent).toContain('"number":"+15550000003"');
  expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  expect(screen.getByText("Telnyx · +15550000003")).toBeInTheDocument();
  fireEvent.click(screen.getByRole("radio", { name: "Web" }));
  expect(screen.getByText("WebRTC")).toBeInTheDocument();
  expect(screen.getByText("—")).toBeInTheDocument();
  expect(screen.getByRole("status").textContent).not.toContain('"number"');
});

test("connection-level errors remain visible alongside the new cards", () => {
  render(<ConnectionFields document={editorFixture} onChange={vi.fn()} participantKey="caller" services={[]} issues={[{ code: "invalid_call_spec", path: ["participants", "caller", "connection"], reason: "Choose a working connection" }]} />);
  expect(screen.getByText("Choose a working connection")).toBeInTheDocument();
});

test.each([
  { numbers: [], message: "Please buy a phone number on the telephony platform." },
  { numbers: [{ id: "used", number: "+15550000001", name: "Support", available: false, assignedTo: ["Support desk"] }], message: "No phone numbers available for use. Please buy a phone number on the telephony platform" }
])("phone inventory guidance: $message", async ({ numbers, message }) => {
  render(<Harness loader={vi.fn<PhoneNumberLoader>().mockResolvedValue({ numbers, nextPage: null })} />);
  fireEvent.click(screen.getByRole("radio", { name: "Phone" }));
  expect(await screen.findByText(message)).toBeInTheDocument();
  expect(screen.queryByText(/Existing voice numbers connected/)).not.toBeInTheDocument();
  expect(screen.getByRole("button", { name: "Assign number" })).toBeDisabled();
});
