import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { ServiceLogo } from "./ServiceLogo";
import { setupProviders } from "./setupCatalog";

afterEach(cleanup);

test("available built-in favicons are bundled and missing favicons use a neutral placeholder", () => {
  render(
    <>
      {setupProviders.map((provider) => (
        <ServiceLogo key={provider.id} provider={provider.id} name={provider.name} />
      ))}
    </>,
  );
  for (const provider of setupProviders) {
    const mark = screen.getByRole("img", { name: `${provider.name} service logo` });
    if (provider.id === "morse_code_api") {
      expect(mark.querySelector("svg")).not.toBeNull();
      expect(mark.textContent).toBe("");
      continue;
    }
    const image = mark.querySelector("img");
    expect(image, provider.id).not.toBeNull();
    expect(image?.getAttribute("src"), provider.id).toMatch(/assets\/icons\/|^data:image\//);
    expect(image?.getAttribute("src"), provider.id).not.toMatch(/^https?:/);
    expect(mark.textContent, provider.id).toBe("");
  }
});
