import { useId, type InputHTMLAttributes, type ReactNode } from "react";
export function FormField({
  label,
  hint,
  error,
  ...props
}: InputHTMLAttributes<HTMLInputElement> & {
  label: string;
  hint?: string;
  error?: string;
}) {
  const id = useId();
  return (
    <div className="access-field">
      <label htmlFor={id}>{label}</label>
      <input
        {...props}
        id={id}
        aria-invalid={error ? true : undefined}
        aria-describedby={error || hint ? `${id}-hint` : undefined}
      />
      {error || hint ? (
        <p
          id={`${id}-hint`}
          className={error ? "access-error" : "access-muted"}
        >
          {error ?? hint}
        </p>
      ) : null}
    </div>
  );
}
export function FormMessage({
  error,
  children,
}: {
  error?: boolean;
  children: ReactNode;
}) {
  return (
    <p
      className={error ? "access-message access-error" : "access-message"}
      role={error ? "alert" : "status"}
    >
      {children}
    </p>
  );
}
