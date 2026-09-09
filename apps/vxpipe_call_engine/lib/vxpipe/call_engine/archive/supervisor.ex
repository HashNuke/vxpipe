defmodule Vxpipe.CallEngine.Archive.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Archive.Subscriber

  def start_link(_options), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @spec open(keyword()) :: {:ok, Vxpipe.CallEngine.Archive.Handoff.t()} | {:error, term()}
  def open(options) when is_list(options) do
    case DynamicSupervisor.start_child(__MODULE__, {Subscriber, options}) do
      {:ok, subscriber} -> {:ok, Subscriber.handoff(subscriber)}
      {:error, reason} -> {:error, reason}
    end
  end
end
