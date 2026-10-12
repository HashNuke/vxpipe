import type { PhoneNumberLoader, PhoneNumber } from "./inspectorTypes";
const numbers: PhoneNumber[] = [
  { id: "demo-1", number: "+15550001000", name: "Reception", available: true, assignedTo: [] },
  { id: "demo-2", number: "+15550002000", name: "Support", available: false, assignedTo: ["Support desk"] },
  { id: "demo-3", number: "+15550003000", name: "Appointments", available: true, assignedTo: [] },
  { id: "demo-4", number: "+15550004000", name: "Billing", available: true, assignedTo: [] },
];
// Storybook data only; the live editor uses createEditorApi.phoneNumbers.
export const storyPhoneNumbers: PhoneNumberLoader = async (_service, search, page, signal) => {
  if (signal.aborted) throw new DOMException("Aborted", "AbortError");
  const results = numbers.filter((item) => `${item.number} ${item.name}`.toLowerCase().includes(search.toLowerCase()));
  const offset = page ? Number(page) : 0;
  return { numbers: results.slice(offset, offset + 3), nextPage: offset + 3 < results.length ? String(offset + 3) : null };
};
export const emptyStoryPhoneNumbers: PhoneNumberLoader = async () => ({ numbers: [], nextPage: null });
export const occupiedStoryPhoneNumbers: PhoneNumberLoader = async () => ({ numbers: numbers.slice(0, 3).map((item) => ({ ...item, available: false, assignedTo: ["Published call spec"] })), nextPage: null });
