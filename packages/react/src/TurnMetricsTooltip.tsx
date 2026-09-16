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
import { Icon } from "./Icon.js";

function metricGroup(metric: Metric) {
  if (
    metric.scope.kind === "room-capability" ||
    metric.scope.kind === "participant-capability"
  )
    return metric.scope.capability;
  return "Turn";
}

function groupMetrics(metrics: readonly Metric[]) {
  const groups = new Map<string, Metric[]>();
  metrics.forEach((metric) => {
    const label = metricGroup(metric);
    groups.set(label, [...(groups.get(label) ?? []), metric]);
  });
  return [...groups.entries()];
}

export function TurnMetricsTooltip({
  metrics,
  speaker,
  time,
  theme,
}: {
  metrics: readonly Metric[];
  speaker: string;
  time: string;
  theme: "light" | "dark";
}) {
  const [open, setOpen] = useState(false);
  const groups = groupMetrics(metrics);
  const { refs, floatingStyles, context } = useFloating({
    open,
    onOpenChange: setOpen,
    placement: "bottom-end",
    whileElementsMounted: autoUpdate,
    middleware: [offset(8), flip(), shift({ padding: 8 })],
  });
  const hover = useHover(context, { move: false });
  const focus = useFocus(context);
  const dismiss = useDismiss(context);
  const role = useRole(context, { role: "tooltip" });
  const { getReferenceProps, getFloatingProps } = useInteractions([
    hover,
    focus,
    dismiss,
    role,
  ]);

  return (
    <>
      <button
        ref={refs.setReference}
        className="vx-turn-metrics-button"
        aria-label={`View metrics for ${speaker} at ${time}`}
        {...getReferenceProps()}
      >
        <Icon name="metrics" />
      </button>
      {open && (
        <FloatingPortal>
          <div
            ref={refs.setFloating}
            className="vx-turn-tooltip"
            data-vx-theme={theme}
            style={floatingStyles}
            {...getFloatingProps()}
          >
            {groups.map(([label, group]) => (
              <section className="vx-turn-metric-group" key={label}>
                <h3>{label}</h3>
                {group.map((metric) => (
                  <div className="vx-turn-metric-row" key={metric.label}>
                    <span>{metric.label}</span>
                    <strong>
                      {metric.value === null
                        ? "Unavailable"
                        : metric.value.toLocaleString()}
                      {metric.value !== null && <small> {metric.unit}</small>}
                    </strong>
                  </div>
                ))}
              </section>
            ))}
          </div>
        </FloatingPortal>
      )}
    </>
  );
}
