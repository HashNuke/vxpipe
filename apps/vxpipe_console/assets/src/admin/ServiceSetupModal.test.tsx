import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import { ServiceSetupModal } from "./ServiceSetupModal";

afterEach(cleanup);

test.each([
  { saved: false, publicKey: false, overriding: false },
  { saved: true, publicKey: false, overriding: false },
  { saved: true, publicKey: true, overriding: false },
  { saved: true, publicKey: true, overriding: true },
])("masks only saved fields when editing: %j", ({ saved, publicKey, overriding }) => {
  render(
    <ServiceSetupModal
      state={{ provider: "telnyx", status: "idle", overriding }}
      connections={
        saved
          ? [{
              provider: "telnyx",
              status: "connected",
              source: overriding ? "platform" : "tenant",
              telephonyPublicKeyConfigured: publicKey,
            }]
          : []
      }
      scope={{ kind: "tenant", tenantKey: "demo", tenantName: "Demo" }}
      publicOrigin="http://localhost:4000"
      onClose={vi.fn()}
      onSelect={vi.fn()}
      onSubmit={vi.fn()}
    />,
  );
  const apiInput = screen.getByLabelText("API key") as HTMLInputElement;
  const publicInput = screen.getByLabelText("Public key") as HTMLInputElement;
  expect(apiInput.placeholder).toBe(saved && !overriding ? "••••••••" : "");
  expect(publicInput.placeholder).toBe(
    saved && publicKey && !overriding ? "••••••••" : "",
  );
  expect(apiInput).toHaveValue("");
  expect(publicInput).toHaveValue("");
});
