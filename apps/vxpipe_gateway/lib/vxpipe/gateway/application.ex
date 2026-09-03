defmodule Vxpipe.Gateway.Application do
  @moduledoc false

  use Application

  alias Vxpipe.Gateway.HTTP

  @impl true
  def start(_type, _args) do
    settings = Application.fetch_env!(:vxpipe_gateway, __MODULE__)

    children =
      settings
      |> Keyword.fetch!(:http)
      |> http_children()

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Vxpipe.Gateway.Supervisor
    )
  end

  defp http_children(http_options) do
    if Keyword.fetch!(http_options, :enabled) do
      [{HTTP.Supervisor, Keyword.delete(http_options, :enabled)}]
    else
      []
    end
  end
end
