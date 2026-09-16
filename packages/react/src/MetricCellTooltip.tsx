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
import type { Metric } from "@vxpipe/core";

function metricValue(metric: Metric | null) {
  if (metric === null || metric.value === null) return "Unavailable";
  return `${metric.value.toLocaleString()} ${metric.unit}`;
}

export function MetricCellTooltip({
  hideUnit,
  label,
  metric,
  target,
  theme,
}: {
  hideUnit: boolean;
  label: string;
  metric: Metric | null;
  target: string;
  theme: "light" | "dark";
}) {
  const [open, setOpen] = useState(false);
  const value = metricValue(metric);
  const { refs, floatingStyles, context } = useFloating({
    open,
    onOpenChange: setOpen,
    placement: "top",
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
        className={`vx-metric-cell ${
          metric === null || metric.value === null
            ? "vx-metric-unavailable"
            : ""
        }`}
        aria-label={`${label} for ${target}: ${value}`}
        {...getReferenceProps()}
      >
        {metric === null || metric.value === null ? (
          <span aria-hidden="true">—</span>
        ) : (
          <>
            <strong>{metric.value.toLocaleString()}</strong>
            {!hideUnit && <small>{metric.unit}</small>}
          </>
        )}
      </button>
      {open && (
        <FloatingPortal>
          <div
            ref={refs.setFloating}
            className="vx-metric-cell-tooltip"
            data-vx-theme={theme}
            style={floatingStyles}
            {...getFloatingProps()}
          >
            <strong>{label}</strong>
            <span>{target}</span>
            <p>
              {metric?.description ??
                "No measurement is available for this target."}
            </p>
            <dl>
              <div>
                <dt>Value</dt>
                <dd>{value}</dd>
              </div>
              {metric && (
                <div>
                  <dt>Source</dt>
                  <dd>{metric.source}</dd>
                </div>
              )}
            </dl>
          </div>
        </FloatingPortal>
      )}
    </>
  );
}
