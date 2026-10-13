import { useState } from "react";
import { Eye, EyeOff } from "lucide-react";
import { FormField } from "./FormField";
export function PasswordFields({
  password,
  confirmation,
  onPassword,
  onConfirmation,
  label = "Password",
  disabled = false,
}: {
  password: string;
  confirmation: string;
  onPassword: (value: string) => void;
  onConfirmation: (value: string) => void;
  label?: string;
  disabled?: boolean;
}) {
  const [visible, setVisible] = useState(false);
  return (
    <div className="access-passwords">
      <FormField
        label={label}
        type={visible ? "text" : "password"}
        autoComplete="new-password"
        required
        maxLength={256}
        value={password}
        onChange={(event) => onPassword(event.target.value)}
        disabled={disabled}
        hint="15–128 characters. Spaces and passphrases are welcome."
      />
      <FormField
        label="Confirm password"
        type={visible ? "text" : "password"}
        autoComplete="new-password"
        required
        value={confirmation}
        onChange={(event) => onConfirmation(event.target.value)}
        disabled={disabled}
      />
      <button
        className="access-text-button"
        type="button"
        onClick={() => setVisible(!visible)}
        aria-pressed={visible}
      >
        {visible ? (
          <EyeOff size={16} aria-hidden />
        ) : (
          <Eye size={16} aria-hidden />
        )}
        {visible ? "Hide passwords" : "Show passwords"}
      </button>
    </div>
  );
}
