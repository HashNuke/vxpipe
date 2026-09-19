defmodule Vxpipe.CallEngine.SpeechExperiment.Scope do
  @moduledoc false
  use DynamicSupervisor

  alias Vxpipe.CallEngine.SpeechExperiment.{Allocation, Control}

  def start_link(options), do: DynamicSupervisor.start_link(__MODULE__, :ok, options)
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_session(scope, options) do
    options =
      options
      |> Keyword.put(:token, make_ref())
      |> Keyword.put_new(:deadline, System.monotonic_time(:millisecond) + 5_000)

    with {:ok, _tree} <- DynamicSupervisor.start_child(scope, {Allocation, options}) do
      control = GenServer.whereis(Control.address(Keyword.fetch!(options, :token)))
      {:ok, control}
    end
  end
end
