import { useEffect, useState } from "react";

import {
  adminStoryPath,
  adminStoryRoute,
  type AdminStoryRoute,
} from "./adminStoryRoute";

export function useAdminStoryNavigation() {
  const [route, setRoute] = useState<AdminStoryRoute>(() =>
    adminStoryRoute(window.location.hash),
  );

  useEffect(() => {
    const syncRoute = () => setRoute(adminStoryRoute(window.location.hash));
    window.addEventListener("popstate", syncRoute);
    window.addEventListener("hashchange", syncRoute);
    return () => {
      window.removeEventListener("popstate", syncRoute);
      window.removeEventListener("hashchange", syncRoute);
    };
  }, []);

  function navigate(nextRoute: AdminStoryRoute) {
    window.history.pushState(
      nextRoute,
      "",
      `#${adminStoryPath(nextRoute)}`,
    );
    setRoute(nextRoute);
  }

  return { route, navigate };
}
