defmodule Vxpipe.CallEngine.Diagnostics.SourceSupervisor do
  @moduledoc "Shared lazy inference and injected collector port; source workers belong to rooms."
  use Supervisor

  alias Vxpipe.CallEngine.Diagnostics.{
    InferenceAdmission,
    SourceAdmission,
    SourceWorker,
    SourcePort
  }

  alias Vxpipe.CallEngine.Speech.{ActivityRuntime, ActivitySupervisor, Silero}

  def child_spec(options),
    do: %{
      id: {__MODULE__, Keyword.fetch!(options, :name)},
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor,
      restart: :temporary
    }

  def start_link(options),
    do: Supervisor.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))

  @doc "Room-owned input worker; the caller must prove its accepted STT binding before attachment."
  def start_input_source(options, workers, runtime, admission) do
    lease = Keyword.fetch!(options, :attachment_lease)

    with {:ok, options} <- inference_options(options, runtime) do
      SourceAdmission.start_worker(admission, lease, workers, {SourceWorker, options})
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp inference_options(options, runtime) do
    case Keyword.get(options, :mode, :benchmark_only) do
      :operational_reuse -> {:ok, Keyword.delete(options, :admission)}
      :benchmark_only -> benchmark_options(options, runtime)
      _ -> {:error, :unsupported_mode}
    end
  end

  defp benchmark_options(options, runtime) do
    case ActivityRuntime.diagnostic_admission(runtime) do
      %InferenceAdmission{} = admission -> {:ok, Keyword.put(options, :admission, admission)}
      _ -> {:error, :unavailable}
    end
  end

  @impl true
  def init(options) do
    options =
      Keyword.validate!(options, [
        :name,
        :inference,
        :tasks,
        :runtime,
        :classify,
        :collector,
        port: SourcePort,
        maximum_sources: 16,
        max_jobs: 1,
        load_timeout_ms: 15_000,
        inference_timeout_ms: 2_000,
        load: &Silero.load/0
      ])

    names =
      Enum.map([:name, :inference, :tasks, :runtime], &Keyword.fetch!(options, &1))

    maximum = Keyword.fetch!(options, :maximum_sources)
    jobs = Keyword.fetch!(options, :max_jobs)

    unless Enum.all?(names, &(is_atom(&1) and &1 != nil)) and length(Enum.uniq(names)) == 4 and
             is_integer(maximum) and maximum in 1..32 and is_integer(jobs) and
             jobs in 1..min(maximum, 8) and
             Keyword.fetch!(options, :load_timeout_ms) in 1..15_000 and
             Keyword.fetch!(options, :inference_timeout_ms) in 1..2_000,
           do: raise(ArgumentError, "invalid diagnostic source pool")

    inference =
      options
      |> Keyword.take([
        :tasks,
        :runtime,
        :load,
        :classify,
        :max_jobs,
        :load_timeout_ms,
        :inference_timeout_ms
      ])
      |> Keyword.put(:name, Keyword.fetch!(options, :inference))
      |> Keyword.put(:diagnostic_capacity, maximum)

    port =
      case Keyword.get(options, :collector) do
        nil ->
          []

        collector when is_function(collector, 1) ->
          [
            {SourcePort,
             name: Keyword.fetch!(options, :port),
             collector: collector,
             runtime: Keyword.fetch!(options, :runtime),
             maximum_sources: maximum}
          ]

        _ ->
          raise ArgumentError, "invalid diagnostic collector"
      end

    Supervisor.init([{ActivitySupervisor, inference}] ++ port, strategy: :one_for_all)
  end
end
