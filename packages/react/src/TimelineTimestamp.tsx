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

const clockFormatter = new Intl.DateTimeFormat(undefined, {
  hour: "numeric",
  minute: "2-digit",
});

const localFormatter = new Intl.DateTimeFormat(undefined, {
  weekday: "long",
  year: "numeric",
  month: "long",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
  second: "2-digit",
  timeZoneName: "long",
});

export function formatTimelineClock(occurredAt: string) {
  return clockFormatter.format(new Date(occurredAt));
}

export function TimelineTimestamp({
  occurredAt,
  theme,
}: {
  occurredAt: string;
  theme: "light" | "dark";
}) {
  const [open, setOpen] = useState(false);
  const instant = new Date(occurredAt);
  const visible = formatTimelineClock(occurredAt);
  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
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
      <time
        ref={refs.setReference}
        className="vx-timestamp"
        dateTime={occurredAt}
        tabIndex={0}
        aria-label={`${visible}; show local and UTC time`}
        {...getReferenceProps()}
      >
        {visible}
      </time>
      {open && (
        <FloatingPortal>
          <div
            ref={refs.setFloating}
            className="vx-timestamp-tooltip"
            data-vx-theme={theme}
            style={floatingStyles}
            {...getFloatingProps()}
          >
            <div>
              <span>Local · {timeZone}</span>
              <strong>{localFormatter.format(instant)}</strong>
            </div>
            <div>
              <span>UTC</span>
              <strong>{instant.toISOString()}</strong>
            </div>
          </div>
        </FloatingPortal>
      )}
    </>
  );
}
