defmodule Vxpipe.CallEngine.Tool.BackgroundSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Tool.BackgroundInvocation

  def start_link(options) do
    genserver_options = Keyword.take(options, [:name])
    DynamicSupervisor.start_link(__MODULE__, options, genserver_options)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :activation_id)},
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @spec start_invocation(DynamicSupervisor.supervisor(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_invocation(supervisor, options) do
    DynamicSupervisor.start_child(supervisor, {BackgroundInvocation, options})
  end

  @impl true
  def init(options) do
    maximum_children = Keyword.fetch!(options, :maximum_children)
    DynamicSupervisor.init(strategy: :one_for_one, max_children: maximum_children)
  end
end
