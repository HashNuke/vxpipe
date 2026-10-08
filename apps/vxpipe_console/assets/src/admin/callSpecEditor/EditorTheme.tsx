import { useLayoutEffect, type ReactNode } from "react";
import { TooltipProvider } from "../components/ui/tooltip";

/** One page editor owns the body portal theme only while it is mounted. */
export function EditorTheme({ theme = "dark", children }: { theme?: "dark" | "light"; children: ReactNode }) {
  useLayoutEffect(() => {
    const previous = document.body.getAttribute("data-admin-editor-theme");
    document.body.setAttribute("data-admin-editor-theme", theme);
    return () => {
      if (previous === null) document.body.removeAttribute("data-admin-editor-theme");
      else document.body.setAttribute("data-admin-editor-theme", previous);
    };
  }, [theme]);
  return <div className="vx-admin" data-theme={theme}><TooltipProvider>{children}</TooltipProvider></div>;
}
