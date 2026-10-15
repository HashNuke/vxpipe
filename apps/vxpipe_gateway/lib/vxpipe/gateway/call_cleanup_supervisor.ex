defmodule Vxpipe.Gateway.CallCleanupSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.Gateway.CallCleanup

  def start_link(_options), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  # Admission may create an owner only for a fresh durable binding. Recovery must
  # use lookup: restarting an empty owner would lose the resource membership.
  def start_new(binding), do: DynamicSupervisor.start_child(__MODULE__, {CallCleanup, binding})

  def lookup(binding) do
    case GenServer.whereis(CallCleanup.name(binding)) do
      pid when is_pid(pid) ->
        _ = CallCleanup.snapshot(pid)
        {:ok, pid}

      nil ->
        {:error, :not_found}
    end
  catch
    :exit, _reason -> {:error, :not_found}
  end
end
