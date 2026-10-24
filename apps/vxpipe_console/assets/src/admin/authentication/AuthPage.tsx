import { useEffect, useRef, useState, type FormEvent } from "react";
import { ArrowLeft, ArrowRight, ShieldCheck } from "lucide-react";
import { Button } from "../Button";
import { FormField, FormMessage } from "./FormField";
import { PasswordFields } from "./PasswordFields";
import { validatePassword } from "./access";
import type { SaveResult } from "./types";
import { normalizeInstanceUrl } from "./instanceUrl";
export function AuthPage({
  mode,
  onSubmit,
  unavailable = false,
  completed = false,
  proofRequired = false,
  configureUrl = false,
}: {
  mode: "setup" | "login" | "recover";
  onSubmit: (email: string, password: string, proof?: string, publicUrl?: string) => Promise<SaveResult>;
  unavailable?: boolean;
  completed?: boolean;
  proofRequired?: boolean;
  /** Opt-in until the installation URL workflow has passed Storybook review. */
  configureUrl?: boolean;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [proof, setProof] = useState("");
  const [error, setError] = useState<string>();
  const [pending, setPending] = useState(false);
  const [step, setStep] = useState<"url" | "account">("url");
  const [publicUrl, setPublicUrl] = useState(() => typeof window === "undefined" ? "" : window.location.origin);
  const heading = useRef<HTMLHeadingElement>(null);
  const firstRender = useRef(true);
  useEffect(() => {
    if (firstRender.current) { firstRender.current = false; return; }
    heading.current?.focus();
  }, [step]);
  const setup = mode === "setup";
  const wizard = setup && configureUrl;
  const recover = mode === "recover";
  const newPassword = setup || recover;
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (wizard && step === "url") {
      const result = normalizeInstanceUrl(publicUrl);
      if ("error" in result) { setError(result.error); return; }
      setPublicUrl(result.url);
      setError(undefined);
      setStep("account");
      return;
    }
    const problem = newPassword
      ? validatePassword(password, confirmation)
      : undefined;
    if (problem) {
      setError(problem);
      return;
    }
    setPending(true);
    try {
      const args = [email.trim(), password, proofRequired || recover ? proof.trim() : undefined] as const;
      const result = await (wizard ? onSubmit(...args, publicUrl) : onSubmit(...args));
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
      <h1 ref={heading} tabIndex={-1}>{wizard ? step === "url" ? "Setup your Installation URL" : "Setup SuperAdmin Account" : setup ? "Set up your installation" : recover ? "Recover Superadmin access" : "Sign in to Vxpipe"}</h1>
      <p className="access-lead">
        {setup
          ? wizard ? step === "url" ? "Choose the address people and connected services use to reach this app." : "Manage your installation, tenants and users with this account." : "Create the first Superadmin account to manage your platform, tenants and users."
          : recover
            ? <>Run <code>mix vxpipe.recover</code> on the server running Vxpipe to get a recovery token. Paste it below to verify access and set a new password.</>
            : "Use your account to open the Console."}
      </p>
      {wizard && !completed ? <ol className="access-setup-steps" aria-label="Setup progress">
        <li aria-current={step === "url" ? "step" : undefined}>1. Configure URL</li>
        <li aria-current={step === "account" ? "step" : undefined}>2. Setup SuperAdmin Account</li>
      </ol> : null}
      {completed ? (
        <FormMessage>
          This installation is already set up. Sign in with an existing account.
        </FormMessage>
      ) : (
        <form className="access-form" onSubmit={submit}>
          {wizard && step === "url" ? <FormField
            label="Installation URL" type="url" required autoComplete="url" spellCheck={false}
            value={publicUrl} onChange={event => { setPublicUrl(event.target.value); setError(undefined); }} disabled={pending}
            hint="Include https:// and a port if needed. You can change this later in Settings → Installation."
          /> : <>
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
          </>}
          {error || unavailable ? (
            <FormMessage error>
              {error ??
                "Sign-in is temporarily unavailable. Try again shortly."}
            </FormMessage>
          ) : null}
          <div className="access-setup-actions">
          {wizard && step === "account" ? <Button type="button" disabled={pending} onClick={() => { setError(undefined); setStep("url"); }}><ArrowLeft size={16} aria-hidden />Back</Button> : null}
          <Button
            type="submit"
            className="access-primary"
            disabled={pending || unavailable}
          >
            {pending
              ? "Please wait…"
              : setup
                ? wizard && step === "url" ? "Continue" : "Create Superadmin account"
                : recover
                  ? "Recover access"
                  : "Sign in"}
            <ArrowRight size={16} aria-hidden />
          </Button>
          </div>
        </form>
      )}
      {!recover && (!wizard || step === "account") ? <p className="access-footnote">
        {setup
          ? "Your email is your sign-in name. No verification email will be sent."
          : <>Forgot your password? Contact an administrator to set a new one. If no Superadmin can sign in, <a href="/auth/recover">use local recovery</a>.</>}
      </p> : null}
    </main>
  );
}
