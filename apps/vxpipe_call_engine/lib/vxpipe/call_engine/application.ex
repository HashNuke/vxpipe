defmodule Vxpipe.CallEngine.Application do
  @moduledoc false

  use Application

  alias Vxpipe.CallEngine.OpeningAudio.AssetCache
  alias Vxpipe.CallEngine.Diagnostics.{AdmissionSupervisor, AttachmentLease, SourceAdmission}

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
      {Registry, keys: :duplicate, name: Vxpipe.CallEngine.ReadinessWatchRegistry},
      {Task.Supervisor, name: Vxpipe.CallEngine.ModelInferenceTaskSupervisor},
      {Task.Supervisor, name: Vxpipe.CallEngine.ArchiveWriterTaskSupervisor},
      {Task.Supervisor, name: Vxpipe.CallEngine.ReadinessTaskSupervisor},
      {Vxpipe.CallEngine.Speech.Silero.ModelCache,
       name: Vxpipe.CallEngine.Speech.Silero.ModelCache},
      {DynamicSupervisor,
       name: Vxpipe.CallEngine.Recording.PreparedWriterSupervisor, strategy: :one_for_one},
      Vxpipe.CallEngine.Archive.Supervisor,
      {Vxpipe.CallEngine.RemoteMCP.CatalogStore, name: Vxpipe.CallEngine.RemoteMCP.CatalogStore},
      {Vxpipe.Providers.ElevenLabs.AgentLeaseSupervisor,
       name: Vxpipe.Providers.ElevenLabs.AgentLeaseSupervisor},
      opening_audio_cache(settings)
    ]

    runtime_children = [
      Vxpipe.CallEngine.RoomSupervisor,
      {Vxpipe.CallEngine.TelemetrySampler,
       name: Vxpipe.CallEngine.TelemetrySampler,
       room_supervisor: Vxpipe.CallEngine.RoomSupervisor,
       sample_interval_ms: Keyword.fetch!(telemetry, :sample_interval_ms)}
    ]

    # Allocate outside AdmissionSupervisor.init so tracker restarts retain capacity.
    # Explicit replacement of this temporary subtree must reuse the original gate.
    admission_children = [
      {AdmissionSupervisor,
       name: AdmissionSupervisor, admission: SourceAdmission, gate: AttachmentLease.gate(32)}
    ]

    base_children ++
      admission_children ++
      model_fixture_children(settings) ++ remote_mcp_children(settings) ++ runtime_children
  end

  defp opening_audio_cache(settings) do
    cache_options = settings |> Keyword.fetch!(:opening_audio) |> Keyword.fetch!(:cache)
    {AssetCache, Keyword.put(cache_options, :name, AssetCache)}
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

  defp remote_mcp_children(settings) do
    options = Keyword.get(settings, :remote_mcp, enabled: false)

    if Keyword.get(options, :enabled, false) do
      task_supervisor = Vxpipe.CallEngine.RemoteMCP.CatalogRefreshTaskSupervisor

      refresher_options =
        options
        |> Keyword.delete(:enabled)
        |> Keyword.put_new(:name, Vxpipe.CallEngine.RemoteMCP.CatalogRefresher)
        |> Keyword.put_new(:task_supervisor, task_supervisor)

      [
        {Task.Supervisor, name: task_supervisor},
        {Vxpipe.CallEngine.RemoteMCP.CatalogRefresher, refresher_options}
      ]
    else
      []
    end
  end
end
