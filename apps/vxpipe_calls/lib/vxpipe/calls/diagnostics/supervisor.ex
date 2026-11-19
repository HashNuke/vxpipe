defmodule Vxpipe.Calls.Diagnostics.Supervisor do
  @moduledoc "Independent capacity for diagnostic persistence, outside call control and publication."
  use Supervisor

  alias Vxpipe.Calls.Diagnostics.{AdmissionGate, Writer}

  def start_link(options) do
    Supervisor.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  def start_writer(options, supervisor \\ Vxpipe.Calls.Diagnostics.WriterSupervisor),
    do: DynamicSupervisor.start_child(supervisor, {Writer, options})

  @impl true
  def init(options) do
    maximum = Keyword.get(options, :maximum_writers, 64)

    if not (is_integer(maximum) and maximum in 1..1_024),
      do: raise(ArgumentError, "invalid diagnostic writer capacity")

    admission_gate = AdmissionGate.new(maximum)

    children = [
      {Task.Supervisor,
       name: Keyword.get(options, :task_supervisor, Vxpipe.Calls.Diagnostics.TaskSupervisor),
       max_children: maximum},
      {DynamicSupervisor,
       strategy: :one_for_one,
       extra_arguments: [admission_gate],
       name: Keyword.get(options, :writer_supervisor, Vxpipe.Calls.Diagnostics.WriterSupervisor),
       max_children: maximum}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
