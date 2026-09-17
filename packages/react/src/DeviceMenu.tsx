import { useRef, useState } from "react";
import {
  autoUpdate,
  flip,
  FloatingFocusManager,
  FloatingPortal,
  offset,
  shift,
  useClick,
  useDismiss,
  useFloating,
  useInteractions,
  useListNavigation,
  useRole,
  useTypeahead,
} from "@floating-ui/react";
import { EllipsisVertical } from "lucide-react";

import { Icon } from "./Icon.js";

export function DeviceMenu({
  devices,
  disabled,
  label,
  onSelect,
  theme,
  value,
}: {
  devices: readonly string[];
  disabled: boolean;
  label: string;
  onSelect: (device: string) => void;
  theme: "light" | "dark";
  value: string;
}) {
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState<number | null>(null);
  const itemRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const labelsRef = useRef<Array<string | null>>([...devices]);
  const { context, floatingStyles, refs } = useFloating({
    open,
    onOpenChange(nextOpen) {
      setOpen(nextOpen);
      if (nextOpen) {
        const selectedIndex = devices.indexOf(value);
        setActiveIndex(selectedIndex >= 0 ? selectedIndex : 0);
      }
    },
    placement: "bottom-start",
    whileElementsMounted: autoUpdate,
    middleware: [offset(6), flip(), shift({ padding: 8 })],
  });
  labelsRef.current = [...devices];
  const { getFloatingProps, getItemProps, getReferenceProps } = useInteractions([
    useClick(context),
    useDismiss(context),
    useListNavigation(context, {
      activeIndex,
      listRef: itemRefs,
      loop: true,
      onNavigate: setActiveIndex,
    }),
    useTypeahead(context, {
      activeIndex,
      listRef: labelsRef,
      onMatch: setActiveIndex,
    }),
    useRole(context, { role: "menu" }),
  ]);

  return (
    <>
      <button
        ref={refs.setReference}
        aria-label={`${label}: ${value}`}
        aria-expanded={open}
        className="vx-button vx-device-menu-trigger"
        disabled={disabled}
        title={`${label}: ${value}`}
        {...getReferenceProps()}
      >
        <EllipsisVertical aria-hidden="true" />
      </button>
      {open ? (
        <FloatingPortal>
          <FloatingFocusManager
            context={context}
            initialFocus={activeIndex ?? 0}
            modal={false}
          >
            <div
              ref={refs.setFloating}
              className="vx-device-menu"
              data-vx-theme={theme}
              style={floatingStyles}
              {...getFloatingProps()}
            >
              <div className="vx-device-menu-heading">
                <span>{label}</span>
                <strong>{value}</strong>
              </div>
              {devices.map((device, index) => (
                <button
                  aria-checked={device === value}
                  key={device}
                  ref={(node) => {
                    itemRefs.current[index] = node;
                  }}
                  role="menuitemradio"
                  tabIndex={activeIndex === index ? 0 : -1}
                  {...getItemProps({
                    onClick() {
                      onSelect(device);
                      setOpen(false);
                    },
                  })}
                >
                  <span>{device}</span>
                  {device === value ? <Icon name="check" /> : null}
                </button>
              ))}
            </div>
          </FloatingFocusManager>
        </FloatingPortal>
      ) : null}
    </>
  );
}
