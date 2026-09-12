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
        {:ok, recovery_children} -> [Vxpipe.Persistence.Repo | recovery_children]
        {:error, reason} -> raise ArgumentError, "invalid publication recovery: #{reason}"
      end
    else
      []
    end
  end
end
