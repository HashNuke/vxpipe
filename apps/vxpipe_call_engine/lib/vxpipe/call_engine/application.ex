defmodule Vxpipe.CallEngine.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    settings = Application.fetch_env!(:vxpipe_call_engine, __MODULE__)
    telemetry = Keyword.fetch!(settings, :telemetry)

    children = [
      {Registry, keys: :unique, name: Vxpipe.CallEngine.RoomRegistry},
      {Task.Supervisor, name: Vxpipe.CallEngine.AudioOutputTaskSupervisor},
      {Task.Supervisor, name: Vxpipe.CallEngine.ModelInferenceTaskSupervisor},
      Vxpipe.CallEngine.Jido,
      Vxpipe.CallEngine.RoomSupervisor,
      {Vxpipe.CallEngine.TelemetrySampler,
       name: Vxpipe.CallEngine.TelemetrySampler,
       room_supervisor: Vxpipe.CallEngine.RoomSupervisor,
       sample_interval_ms: Keyword.fetch!(telemetry, :sample_interval_ms)}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Vxpipe.CallEngine.Supervisor
    )
  end
end
