defmodule Vxpipe.CallEngine.Diagnostics.SourceSupervisor do
  @moduledoc "Separate bounded source and inference supervision; model initialization is lazy."
  use Supervisor
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Capabilities, Participant}
  alias Vxpipe.CallEngine.Diagnostics.{InferenceAdmission, SourceWorker}
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

  @doc "Coordinator-only lifecycle operation; never invoke on the voice admission path."
  def start_source(options, workers, runtime) do
    {agent, options} = Keyword.pop(options, :agent)
    start_eligible_source(agent, options, workers, runtime)
  end

  defp start_eligible_source(
         %Participant{
           kind: :agent,
           capabilities: %Capabilities{
             model_inference: %CapabilitySelection{kind: :model_inference},
             speech_to_speech: nil
           }
         },
         options,
         workers,
         runtime
       ) do
    case ActivityRuntime.diagnostic_admission(runtime) do
      %InferenceAdmission{} = admission ->
        DynamicSupervisor.start_child(
          workers,
          {SourceWorker, Keyword.put(options, :admission, admission)}
        )

      _ ->
        {:error, :unavailable}
    end
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp start_eligible_source(_agent, _options, _workers, _runtime),
    do: {:error, :unsupported_agent}

  @impl true
  def init(options) do
    options =
      Keyword.validate!(options, [
        :name,
        :workers,
        :inference,
        :tasks,
        :runtime,
        :classify,
        maximum_sources: 16,
        max_jobs: 1,
        load_timeout_ms: 15_000,
        inference_timeout_ms: 2_000,
        load: &Silero.load/0
      ])

    names =
      Enum.map([:name, :workers, :inference, :tasks, :runtime], &Keyword.fetch!(options, &1))

    maximum = Keyword.fetch!(options, :maximum_sources)
    jobs = Keyword.fetch!(options, :max_jobs)

    unless Enum.all?(names, &(is_atom(&1) and &1 != nil)) and length(Enum.uniq(names)) == 5 and
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

    Supervisor.init(
      [
        {ActivitySupervisor, inference},
        {DynamicSupervisor,
         name: Keyword.fetch!(options, :workers), strategy: :one_for_one, max_children: maximum}
      ],
      strategy: :one_for_all
    )
  end
end
