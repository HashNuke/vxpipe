defmodule Vxpipe.Calls.Diagnostics.Supervisor do
  @moduledoc "Independent capacity for diagnostic persistence, outside call control and publication."
  use Supervisor

  alias Vxpipe.Calls.Diagnostics.{AdmissionGate, Attachment, Collector, Writer}
  alias Vxpipe.CallEngine.Diagnostics.{AttachmentLease, SettingsProjection, SourceSupervisor}

  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  def start_writer(options, supervisor \\ Vxpipe.Calls.Diagnostics.WriterSupervisor),
    do: DynamicSupervisor.start_child(supervisor, {Writer, options})

  def start_collector(options, supervisor \\ Vxpipe.Calls.Diagnostics.CollectorSupervisor),
    do: DynamicSupervisor.start_child(supervisor, {Collector, options})

  @impl true
  def init(options) do
    maximum = Keyword.get(options, :maximum_writers, 64)

    if not (is_integer(maximum) and maximum in 1..1_024),
      do: raise(ArgumentError, "invalid diagnostic writer capacity")

    collectors = Keyword.get(options, :maximum_collectors, 16)

    if not (is_integer(collectors) and collectors in 1..32),
      do: raise(ArgumentError, "invalid diagnostic collector capacity")

    admission_gate = AdmissionGate.new(maximum)

    children = [
      {Task.Supervisor,
       name: Keyword.get(options, :task_supervisor, Vxpipe.Calls.Diagnostics.TaskSupervisor),
       max_children: maximum},
      {DynamicSupervisor,
       strategy: :one_for_one,
       extra_arguments: [admission_gate],
       name: Keyword.get(options, :writer_supervisor, Vxpipe.Calls.Diagnostics.WriterSupervisor),
       max_children: maximum},
      {DynamicSupervisor,
       strategy: :one_for_one,
       name:
         Keyword.get(options, :collector_supervisor, Vxpipe.Calls.Diagnostics.CollectorSupervisor),
       max_children: collectors}
    ]

    Supervisor.init(children ++ source_children(options, collectors), strategy: :one_for_all)
  end

  defp source_children(options, maximum) do
    case Keyword.get(options, :source_options) do
      nil ->
        []

      source_options when is_list(source_options) ->
        repository = Keyword.fetch!(options, :repository)
        projection = Keyword.get(options, :projection, SettingsProjection)

        factory_options =
          options
          |> Keyword.take([:writer_supervisor, :collector_supervisor, :task_supervisor])
          |> Keyword.put(:repository, repository)
          |> Keyword.put(:projection, projection)

        source_options =
          source_options
          |> Keyword.put(:projection, projection)
          |> Keyword.put(:maximum_sources, maximum)
          |> Keyword.put(:attachment_gate, AttachmentLease.gate(maximum))
          |> Keyword.put(:collector, fn context -> Attachment.start(context, factory_options) end)

        [Supervisor.child_spec({SourceSupervisor, source_options}, restart: :permanent)]
    end
  end
end
