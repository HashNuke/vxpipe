defmodule Vxpipe.CallEngine.Diagnostics.SourcePort do
  @moduledoc "Named injection point for Calls-owned collector and shared inference configuration."
  use GenServer

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))

  def read(name) do
    GenServer.call(name, :read, 250)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @doc "Optional port lifetime fence, shared by attachment proof and workers."
  def current?(nil), do: true
  def current?(pid), do: is_pid(pid) and node(pid) == node() and Process.alive?(pid)

  @impl true
  def init(options) do
    options =
      Keyword.validate!(options, [:name, :runtime, :maximum_sources, :collector])

    maximum = Keyword.fetch!(options, :maximum_sources)
    collector = Keyword.fetch!(options, :collector)

    unless maximum in 1..32 and is_function(collector, 1),
      do: raise(ArgumentError, "invalid diagnostic source port")

    state =
      options |> Keyword.take([:runtime, :maximum_sources, :collector]) |> Map.new()

    {:ok, Map.put(state, :pid, self())}
  end

  @impl true
  def handle_call(:read, _from, state), do: {:reply, {:ok, state}, state}

  @impl true
  def format_status(status),
    do: %{status | state: :redacted, message: :redacted, reason: :redacted, log: []}
end
