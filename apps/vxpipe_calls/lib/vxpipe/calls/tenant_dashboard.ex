defmodule Vxpipe.Calls.TenantDashboard do
  @moduledoc "Minimal authorized tenant overview with independently available recent calls."

  alias Vxpipe.Calls.{CallDirectorySummary, Repositories, TenantDirectory, UserAuthorization}
  alias Vxpipe.Identity.Principal

  @recent_limit 5

  def fetch(%Principal{} = principal, key, options) do
    with {:ok, tenant} <- TenantDirectory.fetch(principal, key, options) do
      dashboard = %{tenant: tenant}

      if UserAuthorization.authorize_tenant(principal, "calls.read", key) == :ok,
        do: {:ok, Map.put(dashboard, :recent_calls, recent_calls(key, options))},
        else: {:ok, dashboard}
    end
  end

  defp recent_calls(key, options) do
    with {:ok, {module, _context} = repository} <- Repositories.fetch(options, :admin_repository),
         true <- Code.ensure_loaded?(module) and function_exported?(module, :recent_calls, 3),
         {:ok, calls} when is_list(calls) <-
           Repositories.call(repository, :recent_calls, [key, @recent_limit]),
         true <-
           length(calls) <= @recent_limit and
             Enum.all?(calls, &match?(%CallDirectorySummary{}, &1)) do
      %{status: :ready, calls: calls}
    else
      _ -> %{status: :unavailable}
    end
  end
end
