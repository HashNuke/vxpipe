import { useId } from "react";

export const credentialInputClass =
  "h-10 w-full rounded-sm border border-[var(--admin-line)] bg-[var(--admin-bg)] px-3 text-sm text-[var(--admin-ink)]";

export type ApiKeyFieldProps = {
  value: string;
  onChange: (value: string) => void;
  disabled: boolean;
  placeholder?: string;
};

export function ApiKeyCredentialFields({
  value,
  onChange,
  disabled,
  placeholder,
}: ApiKeyFieldProps) {
  const id = useId();

  return (
    <div className="grid gap-1.5 text-sm">
      <label className="font-semibold" htmlFor={id}>
        API key
      </label>
      <input
        id={id}
        className={credentialInputClass}
        disabled={disabled}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
        type="password"
        value={value}
      />
    </div>
  );
}
