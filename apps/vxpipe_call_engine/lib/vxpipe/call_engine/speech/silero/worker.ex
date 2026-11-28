defmodule Vxpipe.CallEngine.Speech.Silero.Worker do
  @moduledoc false
  use GenServer

  def start_link(pool), do: GenServer.start_link(__MODULE__, pool)

  @impl true
  def init({pool, run}) do
    :ok = GenServer.call(pool, :register_worker)
    {:ok, {GenServer.whereis(pool), run}}
  end

  @impl true
  def handle_cast({:batch, id, model, rows}, {pool, run} = state) do
    start = System.monotonic_time()
    result = run.(model, rows)
    send(pool, {:settled, self(), id, result, System.monotonic_time() - start})
    {:noreply, state}
  end

  @impl true
  def format_status(status),
    do: %{status | state: :worker, message: :redacted, log: [], reason: :redacted}
end
