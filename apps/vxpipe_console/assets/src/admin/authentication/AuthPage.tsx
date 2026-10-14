import { useState, type FormEvent } from "react";
import { ArrowRight, ShieldCheck } from "lucide-react";
import { Button } from "../Button";
import { FormField, FormMessage } from "./FormField";
import { PasswordFields } from "./PasswordFields";
import { validatePassword } from "./access";
import type { SaveResult } from "./types";
export function AuthPage({
  mode,
  onSubmit,
  unavailable = false,
  completed = false,
  proofRequired = false,
}: {
  mode: "setup" | "login" | "recover";
  onSubmit: (email: string, password: string, proof?: string) => Promise<SaveResult>;
  unavailable?: boolean;
  completed?: boolean;
  proofRequired?: boolean;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [proof, setProof] = useState("");
  const [error, setError] = useState<string>();
  const [pending, setPending] = useState(false);
  const setup = mode === "setup";
  const recover = mode === "recover";
  const newPassword = setup || recover;
  async function submit(event: FormEvent) {
    event.preventDefault();
    const problem = newPassword
      ? validatePassword(password, confirmation)
      : undefined;
    if (problem) {
      setError(problem);
      return;
    }
    setPending(true);
    try {
      const result = await onSubmit(email.trim(), password, proofRequired || recover ? proof.trim() : undefined);
      setError(result.error);
    } catch {
      setError("Unable to connect. Your account has not changed. Try again.");
    } finally {
      setPending(false);
      setPassword("");
      setConfirmation("");
      setProof("");
    }
  }
  return (
    <main className="access-auth">
      <div className="access-auth-mark">
        <ShieldCheck size={26} aria-hidden />
      </div>
      <h1>{setup ? "Set up your installation" : recover ? "Recover Superadmin access" : "Sign in to Vxpipe"}</h1>
      <p className="access-lead">
        {setup
          ? "Create the first Superadmin account to manage your platform, tenants and users."
          : recover
            ? <>Run <code>mix vxpipe.recover</code> on the server running Vxpipe to get a recovery token. Paste it below to verify access and set a new password.</>
            : "Use your account to open the Console."}
      </p>
      {completed ? (
        <FormMessage>
          This installation is already set up. Sign in with an existing account.
        </FormMessage>
      ) : (
        <form className="access-form" onSubmit={submit}>
          <FormField
            label="Email"
            type="email"
            autoComplete="username"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            disabled={pending}
          />
          {newPassword ? (
            <>
              <PasswordFields
                password={password}
                confirmation={confirmation}
                onPassword={setPassword}
                onConfirmation={setConfirmation}
                disabled={pending}
              />
              {proofRequired || recover ? (
                <FormField
                  label={recover ? "Recovery token" : "Local setup proof"}
                  type="password"
                  autoComplete="off"
                  required
                  value={proof}
                  onChange={(event) => setProof(event.target.value)}
                  disabled={pending}
                  hint={recover ? undefined : "Get this one-time proof from the installation operator."}
                />
              ) : null}
            </>
          ) : (
            <FormField
              label="Password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              disabled={pending}
            />
          )}
          {error || unavailable ? (
            <FormMessage error>
              {error ??
                "Sign-in is temporarily unavailable. Try again shortly."}
            </FormMessage>
          ) : null}
          <Button
            type="submit"
            className="access-primary"
            disabled={pending || unavailable}
          >
            {pending
              ? "Please wait…"
              : setup
                ? "Create Superadmin account"
                : recover
                  ? "Recover access"
                  : "Sign in"}
            <ArrowRight size={16} aria-hidden />
          </Button>
        </form>
      )}
      {!recover ? <p className="access-footnote">
        {setup
          ? "Your email is your sign-in name. No verification email will be sent."
          : <>Forgot your password? Contact an administrator to set a new one. If no Superadmin can sign in, <a href="/auth/recover">use local recovery</a>.</>}
      </p> : null}
    </main>
  );
}
