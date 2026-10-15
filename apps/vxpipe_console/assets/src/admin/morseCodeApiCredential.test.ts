import { expect, test } from "vitest";
import { validateCredentialDraft } from "./validateCredentialDraft";

test("Morse compatibility keys follow the HTTP client's header constraints", () => {
  for (const apiKey of ["synthetic", "my compatibility key", " key with punctuation ! "]) {
    expect(validateCredentialDraft({provider: "morse_code_api", values: {apiKey}})).toBeNull();
  }
  for (const apiKey of ["", "   ", "clé", "key\nvalue", "\u007f", "x".repeat(8193)]) {
    expect(validateCredentialDraft({provider: "morse_code_api", values: {apiKey}})).toMatch(/compatibility key/);
  }
  expect(validateCredentialDraft({provider: "elevenlabs", values: {apiKey: "my compatibility key"}})).not.toBeNull();
});
