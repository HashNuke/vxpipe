import { expect, test } from "vitest";
import { onboardingProvider } from "./onboardingFixtures";

test("the onboarding inventory does not label credential-only Rime as speech", () => {
  expect(onboardingProvider("rime", "valid").services).toEqual(["Credentials only"]);
});
