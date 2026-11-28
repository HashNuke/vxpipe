defmodule Vxpipe.CallEngine.Speech.Silero.ModelCache do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.Silero.Model

  def start_link(options),
    do:
      GenServer.start_link(__MODULE__, Keyword.get(options, :load, &Model.load/0),
        name: Keyword.fetch!(options, :name)
      )

  # Only the public immutable model resource crosses this cache. PCM, recurrent
  # stream state, inference tasks and speech allocation authority remain local.
  def fetch(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, :fetch, timeout)
  catch
    :exit, _ -> {:error, :model_unavailable}
  end

  @impl true
  def init(loader), do: {:ok, {:unloaded, loader}}

  @impl true
  def handle_call(:fetch, _from, {:unloaded, loader} = state) do
    case loader.() do
      {:ok, model} -> {:reply, {:ok, model}, model}
      failure -> {:reply, failure, state}
    end
  end

  def handle_call(:fetch, _from, %Model{} = model), do: {:reply, {:ok, model}, model}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, %{model_loaded?: match?(%Model{}, status.state)})
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
