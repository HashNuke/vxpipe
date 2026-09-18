import { useId, useState } from "react";
import { Button } from "./Button";
import { SetupDialog } from "./SetupDialog";

export type TenantCreationStatus = "idle" | "submitting" | "error";

export function CreateTenantModal({
  status,
  onClose,
  onSubmit,
  initialName = "",
}: {
  status: TenantCreationStatus;
  onClose: () => void;
  onSubmit: (name: string) => void;
  initialName?: string;
}) {
  const [name, setName] = useState(initialName);
  const descriptionId = useId();
  const busy = status === "submitting";
  return (
    <SetupDialog busy={busy} onClose={onClose} title="New tenant">
      <p className="setup-create-description" id={descriptionId}>
        Give your tenant a name. Next, you’ll connect its services.
      </p>
      <form
        className="setup-create-form"
        onSubmit={(event) => {
          event.preventDefault();
          if (name.trim() && !busy) onSubmit(name.trim());
        }}
      >
        <label>
          Tenant name
          <input
            aria-describedby={descriptionId}
            autoComplete="off"
            disabled={busy}
            onChange={(event) => setName(event.target.value)}
            placeholder="e.g. Customer Care"
            required
            value={name}
          />
        </label>
        {status === "error" ? (
          <p className="setup-error" role="alert">
            The tenant could not be created. Your name is kept here; try again.
          </p>
        ) : null}
        <div className="setup-create-actions">
          <Button
            disabled={busy}
            onClick={onClose}
            type="button"
            variant="ghost"
          >
            Cancel
          </Button>
          <Button
            className="setup-primary"
            disabled={busy || !name.trim()}
            type="submit"
          >
            {busy ? "Creating…" : "Create tenant"}
          </Button>
        </div>
      </form>
    </SetupDialog>
  );
}
