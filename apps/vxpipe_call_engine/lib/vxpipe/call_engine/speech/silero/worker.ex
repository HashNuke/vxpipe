defmodule Vxpipe.CallEngine.Speech.Silero.Worker do
  @moduledoc false
  use GenServer

  def start_link(pool), do: GenServer.start_link(__MODULE__, pool)

  @impl true
  def init(pool) do
    :ok = GenServer.call(pool, :register_worker)
    {:ok, pool}
  end
end
