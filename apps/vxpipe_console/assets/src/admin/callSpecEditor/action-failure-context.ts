import { createContext, useContext } from "react";

export const ActionFailureContext = createContext<(message: string) => void>(() => {});
export const useActionFailure = () => useContext(ActionFailureContext);
