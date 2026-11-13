import { createContext } from "react";

/** Available binding names for new selections; saved selections retain their binding. */
export const CredentialNamesContext = createContext<Record<string, string[]>>({});
