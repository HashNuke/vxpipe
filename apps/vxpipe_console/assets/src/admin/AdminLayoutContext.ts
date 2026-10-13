import { createContext } from "react";

/** Opt-in composition boundary; existing hosts retain their own frame by default. */
export const AdminLayoutContext = createContext(false);

/** Modal owners disable the shared navigation while their dialog owns focus. */
export const AdminOverlayContext = createContext<(active: boolean) => void>(() => {});
