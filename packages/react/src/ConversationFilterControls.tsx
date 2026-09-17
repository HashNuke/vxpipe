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
import { EllipsisVertical, Wrench } from "lucide-react";

import {
  conversationFilterLabels,
  conversationFilterOrder,
  type ConversationFilter,
  type ConversationFilters,
} from "./conversationFilters.js";
import { Icon } from "./Icon.js";

const filterIcons = {
  messages: "message",
  logs: "log",
  events: "event",
} as const;

function FilterIcon({ filter }: { filter: ConversationFilter }) {
  return filter === "tools" ? (
    <Wrench aria-hidden="true" />
  ) : (
    <Icon name={filterIcons[filter]} />
  );
}

export function ConversationFilterControls({
  filters,
  onReset,
  onToggle,
  theme,
}: {
  filters: ConversationFilters;
  onReset: () => void;
  onToggle: (filter: ConversationFilter) => void;
  theme: "light" | "dark";
}) {
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState<number | null>(null);
  const itemRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const labelsRef = useRef([
    ...conversationFilterOrder.map((filter) => conversationFilterLabels[filter]),
    "Reset",
  ]);
  const { context, floatingStyles, refs } = useFloating({
    open,
    onOpenChange(nextOpen) {
      setOpen(nextOpen);
      if (nextOpen) setActiveIndex(0);
    },
    placement: "bottom-end",
    whileElementsMounted: autoUpdate,
    middleware: [offset(6), flip(), shift({ padding: 8 })],
  });
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
    <div className="vx-conversation-filter-controls">
      <div className="vx-filter-icons" aria-label="Conversation filters">
        {conversationFilterOrder.map((filter) => (
          <button
            aria-label={`${filters[filter] ? "Hide" : "Show"} ${conversationFilterLabels[filter]}`}
            aria-pressed={filters[filter]}
            className={filters[filter] ? `vx-filter-active vx-filter-${filter}` : ""}
            key={filter}
            onClick={() => onToggle(filter)}
            title={conversationFilterLabels[filter]}
          >
            <FilterIcon filter={filter} />
          </button>
        ))}
        <button
          aria-label="Reset filters"
          className="vx-filter-reset"
          onClick={onReset}
          title="Reset filters"
        >
          <Icon name="reset" />
        </button>
      </div>

      <button
        ref={refs.setReference}
        aria-label="Conversation filters"
        aria-expanded={open}
        className="vx-filter-menu-trigger"
        title="Conversation filters"
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
              className="vx-filter-menu"
              data-vx-theme={theme}
              style={floatingStyles}
              {...getFloatingProps()}
            >
              {conversationFilterOrder.map((filter, index) => (
                <button
                  aria-checked={filters[filter]}
                  key={filter}
                  ref={(node) => {
                    itemRefs.current[index] = node;
                  }}
                  role="menuitemcheckbox"
                  tabIndex={activeIndex === index ? 0 : -1}
                  {...getItemProps({ onClick: () => onToggle(filter) })}
                >
                  <FilterIcon filter={filter} />
                  <span>{conversationFilterLabels[filter]}</span>
                  {filters[filter] ? <Icon name="check" /> : null}
                </button>
              ))}
              <button
                ref={(node) => {
                  itemRefs.current[conversationFilterOrder.length] = node;
                }}
                role="menuitem"
                tabIndex={activeIndex === conversationFilterOrder.length ? 0 : -1}
                {...getItemProps({ onClick: onReset })}
              >
                <Icon name="reset" />
                <span>Reset</span>
              </button>
            </div>
          </FloatingFocusManager>
        </FloatingPortal>
      ) : null}
    </div>
  );
}
