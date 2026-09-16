import { useState } from "react";
import {
  autoUpdate,
  flip,
  FloatingPortal,
  offset,
  shift,
  useDismiss,
  useFloating,
  useFocus,
  useHover,
  useInteractions,
  useRole,
} from "@floating-ui/react";

export function MetricHeaderTooltip({
  label,
  shortLabel,
  theme,
}: {
  label: string;
  shortLabel: string;
  theme: "light" | "dark";
}) {
  const [open, setOpen] = useState(false);
  const { refs, floatingStyles, context } = useFloating({
    open,
    onOpenChange: setOpen,
    placement: "bottom",
    whileElementsMounted: autoUpdate,
    middleware: [offset(8), flip(), shift({ padding: 8 })],
  });
  const { getReferenceProps, getFloatingProps } = useInteractions([
    useHover(context, { move: false }),
    useFocus(context),
    useDismiss(context),
    useRole(context, { role: "tooltip" }),
  ]);

  return (
    <>
      <button
        ref={refs.setReference}
        className="vx-metric-header"
        aria-label={`Explain ${label}`}
        {...getReferenceProps()}
      >
        {shortLabel}
      </button>
      {open && (
        <FloatingPortal>
          <div
            ref={refs.setFloating}
            className="vx-metric-header-tooltip"
            data-vx-theme={theme}
            style={floatingStyles}
            {...getFloatingProps()}
          >
            {label}
          </div>
        </FloatingPortal>
      )}
    </>
  );
}
