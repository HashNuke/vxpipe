import { useId, useRef, useEffect, useState } from "react";
import { Button } from "./Button";
import type { TelephonyApplication } from "./telephonyApplicationsApi";

export type ApplicationDraft = {
  name: string;
  provider_connection_id: string;
  outbound_number: string | null;
};

export function TelephonyApplicationForm({
  application,
  pending,
  error,
  onSave,
  onCancel,
}: {
  application: TelephonyApplication | null;
  pending: boolean;
  error: string;
  onSave: (draft: ApplicationDraft) => void;
  onCancel: () => void;
}) {
  const id = useId();
  const first = useRef<HTMLInputElement>(null);
  const [name, setName] = useState(application?.name ?? "");
  const [connection, setConnection] = useState(
    application?.provider_connection_id ?? "",
  );
  const [number, setNumber] = useState(application?.outbound_number ?? "");
  const [validation, setValidation] = useState("");
  useEffect(() => {
    first.current?.focus();
  }, []);
  return (
    <form
      className="setup-create-form phone-application-form"
      aria-label={
        application ? `Edit ${application.name}` : "Add phone application"
      }
      onSubmit={(event) => {
        event.preventDefault();
        const draft = {
          name: name.trim(),
          provider_connection_id: connection.trim(),
          outbound_number: number.trim() || null,
        };
        if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(draft.name)) {
          setValidation(
            "Use 1–128 letters, numbers, hyphens or underscores for the service name.",
          );
          return;
        }
        if (!/^[\x21-\x7e]{1,128}$/.test(draft.provider_connection_id)) {
          setValidation("Enter the Voice API application ID without spaces.");
          return;
        }
        if (
          draft.outbound_number &&
          !/^\+[1-9][0-9]{1,14}$/.test(draft.outbound_number)
        ) {
          setValidation(
            "Use an international caller number, such as +15550002000.",
          );
          return;
        }
        setValidation("");
        onSave(draft);
      }}
    >
      <h3>
        {application ? `Edit ${application.name}` : "Add a Telnyx application"}
      </h3>
      <fieldset disabled={pending} className="phone-application-fields">
        <label>
          Service name
          <input
            ref={!application ? first : undefined}
            value={name}
            readOnly={application !== null}
            onChange={(event) => setName(event.target.value)}
            required
            maxLength={128}
            spellCheck={false}
            aria-describedby={`${id}-name-hint`}
          />
        </label>
        <p id={`${id}-name-hint`}>
          Call specs refer to this name. It stays fixed after saving.
        </p>
        <label>
          Voice API application ID
          <input
            ref={application ? first : undefined}
            value={connection}
            onChange={(event) => setConnection(event.target.value)}
            required
            maxLength={128}
            spellCheck={false}
            aria-describedby={`${id}-application-hint`}
          />
        </label>
        <p id={`${id}-application-hint`}>
          Copy the ID from your Telnyx Voice API application. Use a dedicated
          application for this tenant.
        </p>
        <label>
          Outbound caller number (optional)
          <input
            value={number}
            onChange={(event) => setNumber(event.target.value)}
            type="tel"
            maxLength={16}
            placeholder="+15550002000"
            aria-describedby={`${id}-number-hint`}
          />
        </label>
        <p id={`${id}-number-hint`}>
          Used for outgoing calls. Incoming numbers come from published call
          specs.
        </p>
      </fieldset>
      {validation || error ? (
        <p role="alert" className="phone-application-error">
          {validation || error}
        </p>
      ) : null}
      <div className="setup-create-actions">
        <Button
          type="button"
          variant="ghost"
          disabled={pending}
          onClick={onCancel}
        >
          Cancel
        </Button>
        <Button type="submit" disabled={pending}>
          {pending ? "Saving application…" : "Save application"}
        </Button>
      </div>
    </form>
  );
}
