defmodule Vxpipe.Persistence.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = children()

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Vxpipe.Persistence.Supervisor
    )
  end

  defp children do
    if Application.get_env(:vxpipe_persistence, :enabled, false) do
      recovery_settings =
        Application.get_env(:vxpipe_persistence, :call_details_publication_recovery, [])

      case Vxpipe.Persistence.PublicationRecoveryConfiguration.children(recovery_settings) do
        {:ok, recovery_children} ->
          [Vxpipe.Persistence.Repo] ++ installation_cache_children() ++ recovery_children

        {:error, reason} ->
          raise ArgumentError, "invalid publication recovery: #{reason}"
      end
    else
      []
    end
  end

  defp installation_cache_children do
    [
      {Task.Supervisor, name: Vxpipe.Identity.InstallationURLCache.Tasks},
      {Vxpipe.Identity.InstallationURLCache,
       name: Vxpipe.Identity.InstallationURLCache,
       task_supervisor: Vxpipe.Identity.InstallationURLCache.Tasks,
       loader: &Vxpipe.Persistence.IdentityInstallationStore.fetch/0}
    ]
  end
end
