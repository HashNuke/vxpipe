defmodule Vxpipe.CallEngine.Tool.InvocationSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Tool.Invocation

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
    case prepare_invocation(supervisor, options) do
      {:ok, invocation} ->
        case begin_invocation(invocation) do
          :ok ->
            {:ok, invocation}

          {:error, _reason} = error ->
            _ = DynamicSupervisor.terminate_child(supervisor, invocation)
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  @spec prepare_invocation(DynamicSupervisor.supervisor(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def prepare_invocation(supervisor, options) do
    DynamicSupervisor.start_child(supervisor, {Invocation, options})
  end

  @spec begin_invocation(GenServer.server()) :: :ok | {:error, :already_started | :unavailable}
  def begin_invocation(invocation), do: Invocation.begin(invocation)

  @spec begin_invocation(GenServer.server(), integer()) ::
          :ok | {:error, :already_started | :unavailable}
  def begin_invocation(invocation, admission_deadline),
    do: Invocation.begin(invocation, admission_deadline)

  @impl true
  def init(options) do
    maximum_children = Keyword.fetch!(options, :maximum_children)
    DynamicSupervisor.init(strategy: :one_for_one, max_children: maximum_children)
  end
end
