import { credentialInputClass } from "./ApiKeyCredentialFields";

export function TwilioCredentialFields({
  accountSid,
  onAccountSidChange,
  accountSidPlaceholder,
  authToken,
  onAuthTokenChange,
  authTokenPlaceholder,
  disabled,
}: {
  accountSid: string;
  onAccountSidChange: (value: string) => void;
  accountSidPlaceholder?: string;
  authToken: string;
  onAuthTokenChange: (value: string) => void;
  authTokenPlaceholder?: string;
  disabled: boolean;
}) {
  return (
    <>
      <label className="grid gap-1.5 text-sm font-semibold">
        Account SID
        <input
          className={credentialInputClass}
          disabled={disabled}
          onChange={(event) => onAccountSidChange(event.target.value)}
          placeholder={accountSidPlaceholder}
          type="password"
          value={accountSid}
        />
      </label>
      <label className="grid gap-1.5 text-sm font-semibold">
        Auth token
        <input
          className={credentialInputClass}
          disabled={disabled}
          onChange={(event) => onAuthTokenChange(event.target.value)}
          placeholder={authTokenPlaceholder}
          type="password"
          value={authToken}
        />
      </label>
    </>
  );
}
