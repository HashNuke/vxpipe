import { useId } from "react";

import {
  ApiKeyCredentialFields,
  credentialInputClass,
  type ApiKeyFieldProps,
} from "./ApiKeyCredentialFields";

type Props = ApiKeyFieldProps & {
  showPublicKey: boolean;
  publicKey: string;
  onPublicKeyChange: (value: string) => void;
  publicKeyPlaceholder?: string;
};

export function TelnyxCredentialFields({
  showPublicKey,
  publicKey,
  onPublicKeyChange,
  publicKeyPlaceholder,
  ...apiKey
}: Props) {
  const id = useId();

  return (
    <>
      <ApiKeyCredentialFields {...apiKey} />
      {showPublicKey ? (
        <div className="grid gap-1.5 text-sm">
          <label className="font-semibold" htmlFor={`${id}-public`}>
            Public key
          </label>
          <input
            id={`${id}-public`}
            aria-describedby={`${id}-public-hint`}
            className={credentialInputClass}
            disabled={apiKey.disabled}
            onChange={(event) => onPublicKeyChange(event.target.value)}
            placeholder={publicKeyPlaceholder}
            spellCheck={false}
            type="text"
            value={publicKey}
          />
          <p
            id={`${id}-public-hint`}
            className="text-xs text-[var(--admin-muted)]"
          >
            Note: Public key is only required if you use Telephony services
          </p>
        </div>
      ) : null}
    </>
  );
}
