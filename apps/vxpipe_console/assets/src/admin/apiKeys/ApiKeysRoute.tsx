import { useMemo } from "react";
import { useLocation, useNavigate } from "react-router";
import { NavigationError } from "../navigation/navigationApi";
import { useConsoleNavigation } from "../navigation/navigationContext";
import { AccessKeysApi } from "./accessKeysApi";
import { ApiKeysPage } from "./ApiKeysPage";
export function ApiKeysRoute({ csrfToken, fetchImpl }: { csrfToken: string; fetchImpl?: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response> }) {
  const { fail, data } = useConsoleNavigation();
  const location = useLocation();
  const navigate = useNavigate();
  const api = useMemo(() => new AccessKeysApi(csrfToken, fetchImpl, status => {
    if (status === 401) fail(new NavigationError(status));
  }), [csrfToken, fetchImpl, fail]);
  return <ApiKeysPage key={location.pathname} api={api} authority={data} initialCreating={location.pathname.endsWith("/new")} onCreatingChange={value => { void navigate(value ? "/api-keys/new" : "/api-keys"); }} />;
}
