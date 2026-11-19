defmodule Vxpipe.Calls.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    settings = Application.get_env(:vxpipe_calls, __MODULE__, [])

    Supervisor.start_link(child_specs(settings),
      strategy: :one_for_one,
      name: Vxpipe.Calls.Supervisor
    )
  end

  @doc false
  def child_specs(settings) when is_list(settings) do
    diagnostics =
      case Keyword.get(settings, :diagnostics) do
        nil -> []
        options when is_list(options) -> [{Vxpipe.Calls.Diagnostics.Supervisor, options}]
      end

    [Vxpipe.Calls.PublicationSupervisor] ++ diagnostics
  end
end
