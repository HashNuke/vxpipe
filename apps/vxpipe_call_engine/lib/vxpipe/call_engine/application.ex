defmodule Vxpipe.CallEngine.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    settings = Application.fetch_env!(:vxpipe_call_engine, __MODULE__)

    Supervisor.start_link(child_specs(settings),
      strategy: :one_for_one,
      name: Vxpipe.CallEngine.Supervisor
    )
  end

  @doc false
  def child_specs(settings) when is_list(settings) do
    telemetry = Keyword.fetch!(settings, :telemetry)

    base_children = [
      {Registry, keys: :unique, name: Vxpipe.CallEngine.RoomRegistry},
      {Task.Supervisor, name: Vxpipe.CallEngine.AudioOutputTaskSupervisor},
      {Task.Supervisor, name: Vxpipe.CallEngine.ModelInferenceTaskSupervisor},
      {Task.Supervisor, name: Vxpipe.CallEngine.ArchiveWriterTaskSupervisor},
      Vxpipe.CallEngine.Archive.Supervisor,
      Vxpipe.CallEngine.Jido
    ]

    runtime_children = [
      Vxpipe.CallEngine.RoomSupervisor,
      {Vxpipe.CallEngine.TelemetrySampler,
       name: Vxpipe.CallEngine.TelemetrySampler,
       room_supervisor: Vxpipe.CallEngine.RoomSupervisor,
       sample_interval_ms: Keyword.fetch!(telemetry, :sample_interval_ms)}
    ]

    base_children ++ model_fixture_children(settings) ++ runtime_children
  end

  defp model_fixture_children(settings) do
    options = Keyword.get(settings, :model_fixture, enabled: false)

    if Keyword.get(options, :enabled, false) do
      fixture_options =
        options
        |> Keyword.delete(:enabled)
        |> Keyword.put_new(:name, Vxpipe.CallEngine.Diagnostics.ModelFixture)

      [{Vxpipe.CallEngine.Diagnostics.ModelFixture, fixture_options}]
    else
      []
    end
  end
end
