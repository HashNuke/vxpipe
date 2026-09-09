defmodule Vxpipe.CallEngine.TestRecoveringArchiveWriter do
  @moduledoc false

  use Agent

  def start_link(options) do
    mode = Keyword.get(options, :mode, :unavailable)
    observer = Keyword.fetch!(options, :observer)
    Agent.start_link(fn -> %{facts: [], mode: mode, observer: observer} end)
  end

  def write(server, fact) do
    {mode, observer} = Agent.get(server, &{&1.mode, &1.observer})

    send(observer, {:test_archive_attempt, fact, mode})

    case mode do
      :available ->
        Agent.update(server, fn state -> %{state | facts: [fact | state.facts]} end)
        send(observer, {:test_archive_stored, fact})
        :ok

      :unavailable ->
        {:retry, :database_unavailable}

      :raise ->
        raise "simulated archive adapter crash"
    end
  end

  def recover(server), do: Agent.update(server, &%{&1 | mode: :available})
  def facts(server), do: Agent.get(server, &Enum.reverse(&1.facts))
end
