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
import { Info } from "lucide-react";

export function MetricDescriptionTooltip({
  label,
  description,
  theme,
}: {
  label: string;
  description: string;
  theme: "light" | "dark";
}) {
  const [open, setOpen] = useState(false);
  const { refs, floatingStyles, context } = useFloating({
    open,
    onOpenChange: setOpen,
    placement: "top-start",
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
        className="vx-metric-explanation"
        aria-label={`Explain ${label}`}
        {...getReferenceProps()}
      >
        <strong>{label}</strong>
        <Info aria-hidden="true" />
      </button>
      {open && (
        <FloatingPortal>
          <div
            ref={refs.setFloating}
            className="vx-metric-description-tooltip"
            data-vx-theme={theme}
            style={floatingStyles}
            {...getFloatingProps()}
          >
            {description}
          </div>
        </FloatingPortal>
      )}
    </>
  );
}
