import { ChevronDown, Copy, Eye, EyeOff, Plus, Trash2 } from "lucide-react";
import {
  useId,
  useState,
  type ChangeEventHandler,
  type InputHTMLAttributes,
  type ReactNode,
} from "react";
import { Button } from "../Button";
import type { Pair } from "./fixtures";

export function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: (id: string, hintId: string | undefined) => ReactNode;
}) {
  const id = useId();
  return (
    <div className="mcp-field">
      <label htmlFor={id}>{label}</label>
      <div>
        {children(id, hint ? `${id}-hint` : undefined)}
        {hint && (
          <p id={`${id}-hint`} className="mcp-hint">
            {hint}
          </p>
        )}
      </div>
    </div>
  );
}
export function TextField({
  label,
  hint,
  secret,
  multiline,
  ...props
}: Omit<InputHTMLAttributes<HTMLInputElement>, "onChange"> & {
  label: string;
  hint?: string;
  secret?: boolean;
  multiline?: boolean;
  onChange?: ChangeEventHandler<HTMLInputElement | HTMLTextAreaElement>;
}) {
  const [visible, setVisible] = useState(false);
  return (
    <Field label={label} hint={hint}>
      {(id, hintId) => (
        <div className="mcp-secret-field">
          {multiline && (!secret || visible) ? (
            <textarea
              id={id}
              aria-describedby={hintId}
              rows={4}
              value={String(props.value ?? "")}
              placeholder={props.placeholder}
              onChange={props.onChange}
              spellCheck={false}
              autoComplete="off"
            />
          ) : (
            <input
              {...props}
              id={id}
              aria-describedby={hintId}
              type={secret && !visible ? "password" : (props.type ?? "text")}
              autoComplete={secret ? "off" : props.autoComplete}
              spellCheck={false}
            />
          )}
          {secret && (
            <Button
              type="button"
              variant="ghost"
              aria-label={`${visible ? "Hide" : "Show"} ${label.toLowerCase()}`}
              onClick={() => setVisible(!visible)}
            >
              {visible ? (
                <EyeOff size={16} aria-hidden />
              ) : (
                <Eye size={16} aria-hidden />
              )}
            </Button>
          )}
        </div>
      )}
    </Field>
  );
}
export function SelectField({
  label,
  value,
  onChange,
  children,
  hint,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  children: ReactNode;
  hint?: string;
}) {
  return (
    <Field label={label} hint={hint}>
      {(id, hintId) => (
        <select
          id={id}
          aria-describedby={hintId}
          value={value}
          onChange={(event) => onChange(event.target.value)}
        >
          {children}
        </select>
      )}
    </Field>
  );
}
export function Disclosure({
  title,
  children,
  initialOpen = false,
}: {
  title: string;
  children: ReactNode;
  initialOpen?: boolean;
}) {
  const [open, setOpen] = useState(initialOpen);
  const id = useId();
  return (
    <section className="mcp-disclosure">
      <button
        type="button"
        aria-expanded={open}
        aria-controls={id}
        onClick={() => setOpen(!open)}
      >
        {title}
        <ChevronDown
          className={open ? "mcp-chevron-open" : ""}
          size={16}
          aria-hidden
        />
      </button>
      {open && (
        <div id={id} className="mcp-disclosure-content">
          {children}
        </div>
      )}
    </section>
  );
}
export function CopyField({ label, value }: { label: string; value: string }) {
  const [status, setStatus] = useState("");
  return (
    <Field label={label}>
      {(id) => (
        <>
          <div className="mcp-copy-field">
            <input id={id} value={value} readOnly />
            <Button
              type="button"
              aria-label={`Copy ${label.toLowerCase()}`}
              onClick={async () => {
                try {
                  await navigator.clipboard.writeText(value);
                  setStatus("Copied");
                } catch {
                  setStatus("Select the URL to copy it.");
                }
              }}
            >
              <Copy size={15} aria-hidden />
            </Button>
          </div>
          {status && (
            <p className="mcp-hint" role="status">
              {status}
            </p>
          )}
        </>
      )}
    </Field>
  );
}
export function Pairs({
  label,
  singular,
  pairs,
  onChange,
  secret = false,
}: {
  label: string;
  singular: string;
  pairs: Pair[];
  onChange: (value: Pair[]) => void;
  secret?: boolean;
}) {
  const id = useId();
  return (
    <fieldset className="mcp-pairs">
      <legend>{label}</legend>
      {pairs.map((pair, index) => (
        <div className="mcp-pair" key={pair.id}>
          <label className="sr-only" htmlFor={`${id}-name-${pair.id}`}>
            {singular} name {index + 1}
          </label>
          <input
            id={`${id}-name-${pair.id}`}
            placeholder="Name"
            value={pair.name}
            onChange={(event) =>
              onChange(
                pairs.map((row) =>
                  row.id === pair.id
                    ? { ...row, name: event.target.value }
                    : row,
                ),
              )
            }
            autoComplete="off"
            spellCheck={false}
          />
          <label className="sr-only" htmlFor={`${id}-value-${pair.id}`}>
            {singular} value {index + 1}
          </label>
          <input
            id={`${id}-value-${pair.id}`}
            placeholder="Value"
            type={secret ? "password" : "text"}
            value={pair.value}
            onChange={(event) =>
              onChange(
                pairs.map((row) =>
                  row.id === pair.id
                    ? { ...row, value: event.target.value }
                    : row,
                ),
              )
            }
            autoComplete="off"
            spellCheck={false}
          />
          <Button
            type="button"
            variant="ghost"
            aria-label={`Remove ${singular.toLowerCase()} ${index + 1}`}
            onClick={() => onChange(pairs.filter((row) => row.id !== pair.id))}
          >
            <Trash2 size={16} aria-hidden />
          </Button>
        </div>
      ))}
      <Button
        type="button"
        variant="ghost"
        className="mcp-add-pair"
        onClick={() =>
          onChange([
            ...pairs,
            {
              id: Math.max(0, ...pairs.map((pair) => pair.id)) + 1,
              name: "",
              value: "",
            },
          ])
        }
      >
        <Plus size={14} aria-hidden />
        Add {singular.toLowerCase()}
      </Button>
    </fieldset>
  );
}
