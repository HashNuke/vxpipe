defmodule Vxpipe.Gateway.HTTP.Supervisor do
  @moduledoc false

  use Supervisor

  alias Vxpipe.Gateway.HTTP.Endpoint

  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(options) do
    endpoint_options =
      Keyword.take(options, [:call_admission, :cors, :room_creation, :telephony, :webrtc])

    children = [
      {Bandit,
       plug: {Endpoint, endpoint_options},
       ip: Keyword.fetch!(options, :ip),
       port: Keyword.fetch!(options, :port)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
