import { useState, type FormEvent, type ReactNode } from "react";
import { Button } from "../Button";
import { PageHeader } from "../PageHeader";
import { FormField, FormMessage } from "./FormField";
import { PasswordFields } from "./PasswordFields";
import { RoleBadge } from "./RoleBadge";
import { validatePassword } from "./access";
import type { Role, SaveResult, User } from "./types";
export function AccountPage({
  user,
  role,
  onSave,
  connectedClients,
}: {
  user: User;
  role: Role;
  connectedClients?: ReactNode;
  onSave: (
    email: string,
    currentPassword: string,
    password?: string,
    confirmation?: string,
  ) => Promise<SaveResult>;
}) {
  const [email, setEmail] = useState(user.email);
  const [current, setCurrent] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [changePassword, setChangePassword] = useState(false);
  const [error, setError] = useState<string>();
  const [saved, setSaved] = useState(false);
  const [pending, setPending] = useState(false);
  async function submit(event: FormEvent) {
    event.preventDefault();
    setSaved(false);
    const problem = changePassword
      ? validatePassword(password, confirmation)
      : undefined;
    if (problem) {
      setError(problem);
      return;
    }
    setPending(true);
    try {
      const result = await onSave(
        email.trim(),
        current,
        changePassword ? password : undefined,
        changePassword ? confirmation : undefined,
      );
      setError(result.error);
      setSaved(!result.error);
    } catch {
      setError("Your account could not be updated. Try again.");
    } finally {
      setPending(false);
      setCurrent("");
      setPassword("");
      setConfirmation("");
    }
  }
  return (
    <main className="access-page access-narrow">
      <PageHeader
        title="Your account"
        description="Manage your sign-in details."
      />
      <div className="access-account-role">
        <RoleBadge role={role} />
        <span className="access-muted">
          Role changes are managed by an administrator.
        </span>
      </div>
      <form className="access-form" onSubmit={submit}>
        <FormField
          label="Email"
          type="email"
          required
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          autoComplete="username"
        />
        <FormField
          label="Current password"
          type="password"
          required
          value={current}
          onChange={(event) => setCurrent(event.target.value)}
          autoComplete="current-password"
          hint="Confirm your current password to save account changes."
        />
        <label className="access-check">
          <input
            type="checkbox"
            checked={changePassword}
            onChange={(event) => setChangePassword(event.target.checked)}
          />
          Change password
        </label>
        {changePassword ? (
          <PasswordFields
            label="New password"
            password={password}
            confirmation={confirmation}
            onPassword={setPassword}
            onConfirmation={setConfirmation}
            disabled={pending}
          />
        ) : null}
        {error ? <FormMessage error>{error}</FormMessage> : null}
        {saved ? <FormMessage>Account updated.</FormMessage> : null}
        <Button className="access-primary" type="submit" disabled={pending}>
          {pending ? "Saving…" : "Save changes"}
        </Button>
      </form>
      {connectedClients}
    </main>
  );
}
