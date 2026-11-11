import { afterEach, expect, test, vi } from "vitest";
import { deliverCallback, prepareReceipt } from "./oauthReceiptTransport";

afterEach(() => { document.body.replaceChildren(); vi.restoreAllMocks(); });

test("a receipt targets a new named window while retaining the native decision form", () => {
  const form = document.createElement("form");
  form.action = "/oauth/authorize/request";
  const open = vi.spyOn(window, "open").mockReturnValue({} as Window);
  expect(prepareReceipt(form, "request")).toBe(true);
  expect(open).toHaveBeenCalledWith("", "vxpipe-consent-request");
  expect(form.target).toBe("vxpipe-consent-request");
  expect(new FormData(form).get("presentation")).toBe("receipt");
  expect(form.getAttribute("action")).toBe("/oauth/authorize/request");
});

test.each([null, { closed: true }])("blocked or detached windows leave the native callback intact", (receipt) => {
  const form = document.createElement("form");
  vi.spyOn(window, "open").mockReturnValue(receipt as Window | null);
  expect(prepareReceipt(form, "request")).toBe(false);
  expect(form.target).toBe("");
  expect(new FormData(form).has("presentation")).toBe(false);
});

const completion = { request_id: "request", callback: "https://client.example/callback?code=code&state=state", expires_at: "2026-12-11T00:00:00Z" };
function browser(opener: unknown) {
  return { opener, location: { origin: "https://vxpipe.example", replace: vi.fn() } } as unknown as Window;
}

test("only the original same-origin request window receives the callback and the opener is severed", () => {
  const replace = vi.fn();
  const original = { closed: false, location: { origin: "https://vxpipe.example", pathname: "/oauth/authorize/request", replace } };
  const receipt = browser(original);
  deliverCallback(completion, receipt);
  expect(replace).toHaveBeenCalledExactlyOnceWith(completion.callback);
  expect(receipt.location.replace).not.toHaveBeenCalled();
  expect(receipt.opener).toBeNull();
});

test.each([null, { closed: true }, { closed: false, location: { origin: "https://elsewhere.example" } }, { closed: false, location: { origin: "https://vxpipe.example", pathname: "/account" } }])(
  "a missing or unrelated opener uses the receipt window for compatible callback delivery", (opener) => {
    const receipt = browser(opener);
    deliverCallback(completion, receipt);
    expect(receipt.location.replace).toHaveBeenCalledExactlyOnceWith(completion.callback);
    expect(receipt.opener).toBeNull();
  },
);

test("a denied cross-origin opener read falls back without losing the callback", () => {
  const receipt = browser({ get location() { throw new DOMException("Cross origin", "SecurityError"); } });
  deliverCallback(completion, receipt);
  expect(receipt.location.replace).toHaveBeenCalledExactlyOnceWith(completion.callback);
  expect(receipt.opener).toBeNull();
});
