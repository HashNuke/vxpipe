import { Check, Copy } from "lucide-react";
import { useEffect, useId, useRef, useState } from "react";
import { Button } from "./Button";
import "./copy-button.css";

type CopyButtonProps = {
  value: string;
  label?: string;
  "aria-label"?: string;
  disabled?: boolean;
  errorMessage?: string;
};

/** Shared clipboard action: fixed-width feedback, a two-second reset, and manual recovery. */
export function CopyButton(props: CopyButtonProps) {
  return <CopyAction key={props.value} {...props} />;
}

function CopyAction({ value, label = "Copy", "aria-label": ariaLabel, disabled,
  errorMessage = "Copy failed. Select the value and copy it manually.",
}: CopyButtonProps) {
  const errorId = useId();
  const [state, setState] = useState<"idle" | "copying" | "copied" | "error">("idle");
  const active = useRef(true);
  const resetTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
      if (resetTimer.current !== null) clearTimeout(resetTimer.current);
    };
  }, []);

  async function copy() {
    if (resetTimer.current !== null) clearTimeout(resetTimer.current);
    setState("copying");
    try {
      await navigator.clipboard.writeText(value);
      if (!active.current) return;
      setState("copied");
      resetTimer.current = setTimeout(() => setState("idle"), 2000);
    } catch {
      if (active.current) setState("error");
    }
  }

  return <span className="copy-action">
    <Button type="button" aria-label={ariaLabel ?? label}
      aria-describedby={state === "error" ? errorId : undefined}
      disabled={disabled || state === "copying"} onClick={() => void copy()}>
      {state === "copied" ? <Check size={16} aria-hidden="true" /> : <Copy size={16} aria-hidden="true" />}
      <span className="copy-button-label" data-label={label}>
        <span aria-live="polite">{state === "copied" ? "Copied" : label}</span>
      </span>
    </Button>
    {state === "error" ? <span className="copy-button-error" id={errorId} role="alert">{errorMessage}</span> : null}
  </span>;
}
