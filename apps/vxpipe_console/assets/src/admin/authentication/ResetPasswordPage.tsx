import { useState, type FormEvent } from "react";
import { ArrowLeft } from "lucide-react";
import { Button } from "../Button";
import { PageHeader } from "../PageHeader";
import { canManageUser, validatePassword } from "./access";
import { FormMessage } from "./FormField";
import { PasswordFields } from "./PasswordFields";
import type { Navigate, Role, SaveResult, User } from "./types";
export function ResetPasswordPage({
  actorRole,
  targetRole,
  user,
  onReset,
  onNavigate,
}: {
  actorRole: Role;
  targetRole: Role;
  user: User;
  onReset: (password: string) => Promise<SaveResult>;
  onNavigate: Navigate;
}) {
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState<string>();
  const [saved, setSaved] = useState(false);
  const [pending, setPending] = useState(false);
  if (!canManageUser(actorRole, targetRole))
    return (
      <main className="access-page">
        <PageHeader
          title="Access unavailable"
          description="Your role cannot reset this account's password."
        />
      </main>
    );
  async function submit(event: FormEvent) {
    event.preventDefault();
    setSaved(false);
    const problem = validatePassword(password, confirmation);
    if (problem) {
      setError(problem);
      return;
    }
    setPending(true);
    try {
      const result = await onReset(password);
      setError(result.error);
      setSaved(!result.error);
    } catch {
      setError("Password could not be saved. Try again.");
    } finally {
      setPending(false);
      setPassword("");
      setConfirmation("");
    }
  }
  return (
    <main className="access-page access-narrow">
      <a
        className="access-back"
        href={`/admin/users/${user.id}`}
        onClick={(event) => {
          event.preventDefault();
          onNavigate(`/admin/users/${user.id}`);
        }}
      >
        <ArrowLeft size={16} aria-hidden />
        Back to user
      </a>
      <PageHeader
        title="Reset password"
        description={`Set a new password for ${user.email}.`}
      />
      <p className="access-muted">
        Their current sessions will be signed out. No email will be sent.
      </p>
      <form className="access-form" onSubmit={submit}>
        <PasswordFields
          password={password}
          confirmation={confirmation}
          onPassword={setPassword}
          onConfirmation={setConfirmation}
          label="New password"
          disabled={pending}
        />
        {error ? <FormMessage error>{error}</FormMessage> : null}
        {saved ? (
          <FormMessage>
            Password updated. The user can sign in with the new password.
          </FormMessage>
        ) : null}
        <div className="access-actions">
          <Button className="access-primary" type="submit" disabled={pending}>
            {pending ? "Saving…" : "Set password"}
          </Button>
          <Button
            type="button"
            variant="ghost"
            onClick={() => onNavigate(`/admin/users/${user.id}`)}
          >
            Cancel
          </Button>
        </div>
      </form>
    </main>
  );
}
