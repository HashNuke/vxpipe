import { X } from "lucide-react";
import {
  useEffect,
  useId,
  useRef,
  type KeyboardEvent,
  type ReactNode,
} from "react";
import { Button } from "./Button";

export function SetupDialog({
  title,
  headerContent,
  children,
  onClose,
  busy = false,
  anchorTop = false,
}: {
  title: string;
  headerContent?: ReactNode;
  children: ReactNode;
  onClose: () => void;
  busy?: boolean;
  anchorTop?: boolean;
}) {
  const titleId = useId();
  const dialogRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const previous =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null;
    const dialog = dialogRef.current;
    (
      dialog?.querySelector<HTMLElement>(
        "input:not([disabled]), select:not([disabled])",
      ) ??
      dialog?.querySelector<HTMLElement>("button:not([disabled])") ??
      dialog
    )?.focus();
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previousOverflow;
      previous?.focus();
    };
  }, []);

  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape" && !busy) {
      event.preventDefault();
      onClose();
    }
    if (event.key !== "Tab") return;
    const items = Array.from(
      dialogRef.current?.querySelectorAll<HTMLElement>(
        "button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), a[href]",
      ) ?? [],
    );
    const first = items[0];
    const last = items[items.length - 1];
    if (!first) {
      event.preventDefault();
      return;
    }
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  return (
    <div
      className={`setup-dialog-backdrop${anchorTop ? " setup-dialog-backdrop--anchored" : ""}`}
      onClick={(event) => {
        if (event.target === event.currentTarget && !busy) onClose();
      }}
    >
      <div
        aria-labelledby={titleId}
        aria-modal="true"
        className="setup-dialog"
        onKeyDown={handleKeyDown}
        ref={dialogRef}
        role="dialog"
        tabIndex={-1}
      >
        <header className="setup-dialog-header">
          <h2 className={headerContent ? "sr-only" : undefined} id={titleId}>
            {title}
          </h2>
          {headerContent}
          <Button
            aria-label="Close dialog"
            disabled={busy}
            onClick={onClose}
            variant="ghost"
          >
            <X aria-hidden="true" size={18} />
          </Button>
        </header>
        {children}
      </div>
    </div>
  );
}
