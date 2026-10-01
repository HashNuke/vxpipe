defmodule Vxpipe.CallEngine.Speech.Silero.ModelCache do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.Silero.Model

  def start_link(options),
    do: GenServer.start_link(__MODULE__, :not_loaded, name: Keyword.fetch!(options, :name))

  # Only the public immutable model resource crosses this cache. PCM, recurrent
  # stream state, inference tasks and speech allocation authority remain local.
  def fetch, do: GenServer.call(__MODULE__, :fetch, 5_000)

  @impl true
  def init(:not_loaded), do: {:ok, nil}

  @impl true
  def handle_call(:fetch, _from, nil) do
    case Model.load() do
      {:ok, model} -> {:reply, {:ok, model}, model}
      failure -> {:reply, failure, nil}
    end
  end

  def handle_call(:fetch, _from, %Model{} = model), do: {:reply, {:ok, model}, model}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, %{model_loaded?: not is_nil(status.state)})
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
