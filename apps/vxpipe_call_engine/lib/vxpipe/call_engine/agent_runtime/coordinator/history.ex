defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator.History do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}

  @derive {Inspect, only: [:maximum_entries]}
  @enforce_keys [:entries, :maximum_entries]
  defstruct @enforce_keys

  @type identity :: {String.t(), String.t(), String.t()}
  @type entry :: {identity(), map()}
  @type t :: %__MODULE__{entries: [entry()], maximum_entries: pos_integer()}

  @spec new(pos_integer()) :: t()
  def new(maximum_entries) when is_integer(maximum_entries) and maximum_entries > 0 do
    %__MODULE__{entries: [], maximum_entries: maximum_entries}
  end

  @spec record(t(), SendText.t() | ContinueAgent.t(), map()) :: t()
  def record(%__MODULE__{} = history, command, correlation) when is_map(correlation) do
    identity = identity(command)

    entries =
      history.entries
      |> Enum.reject(fn {existing, _correlation} -> existing == identity end)
      |> then(&[{identity, correlation} | &1])
      |> Enum.take(history.maximum_entries)

    %{history | entries: entries}
  end

  @spec select(t(), [identity()]) :: {[map()], t()}
  def select(%__MODULE__{} = history, identities) when is_list(identities) do
    selected = MapSet.new(identities)

    {discarded, retained} =
      Enum.split_with(history.entries, fn {identity, _correlation} ->
        MapSet.member?(selected, identity)
      end)

    correlations = Enum.map(discarded, fn {_identity, correlation} -> correlation end)
    {correlations, %{history | entries: retained}}
  end

  defp identity(%module{} = command) when module in [SendText, ContinueAgent] do
    {command.connection_id, command.correlation_id, command.id}
  end
end
