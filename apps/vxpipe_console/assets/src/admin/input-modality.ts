import { useEffect } from "react";

let subscribers = 0;
let unsubscribe = () => {};

/** Keep pointer-triggered and restored button focus separate from keyboard focus. */
export function useInputModality() {
  useEffect(() => {
    if (subscribers++ === 0) {
      const root = document.documentElement;
      const previous = root.getAttribute("data-admin-input");
      const pointer = () => root.setAttribute("data-admin-input", "pointer");
      const keyboard = (event: KeyboardEvent) => {
        if (["Shift", "Control", "Alt", "Meta"].includes(event.key) || event.metaKey || event.ctrlKey || event.altKey) return;
        root.setAttribute("data-admin-input", "keyboard");
      };
      document.addEventListener("pointerdown", pointer, true);
      document.addEventListener("keydown", keyboard, true);
      unsubscribe = () => {
        document.removeEventListener("pointerdown", pointer, true);
        document.removeEventListener("keydown", keyboard, true);
        if (previous === null) root.removeAttribute("data-admin-input");
        else root.setAttribute("data-admin-input", previous);
      };
    }
    return () => { if (--subscribers === 0) unsubscribe(); };
  }, []);
}
