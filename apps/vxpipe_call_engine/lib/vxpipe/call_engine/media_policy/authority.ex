defmodule Vxpipe.CallEngine.MediaPolicy.Authority do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.{MediaPolicy, Participant}

  @call_timeout 5_000

  def start_link(options) do
    name = if Keyword.get(options, :register, true), do: via(options), else: nil
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      significant: true
    }
  end

  @spec whereis(String.t()) :: pid() | nil
  def whereis(incarnation_id) when is_binary(incarnation_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, registry_key(incarnation_id)) do
      [{server, _value}] -> server
      [] -> nil
    end
  end

  @spec snapshot(GenServer.server(), timeout()) :: Snapshot.t()
  def snapshot(server, timeout \\ @call_timeout), do: GenServer.call(server, :snapshot, timeout)

  @spec admit(GenServer.server(), String.t(), timeout()) ::
          {:ok, Snapshot.t()} | {:error, :already_present | :unknown_participant}
  def admit(server, participant_id, timeout \\ @call_timeout) when is_binary(participant_id) do
    GenServer.call(server, {:admit, participant_id}, timeout)
  end

  @spec leave(GenServer.server(), String.t(), timeout()) ::
          {:ok, Snapshot.t()} | {:error, :not_present}
  def leave(server, participant_id, timeout \\ @call_timeout) when is_binary(participant_id) do
    GenServer.call(server, {:leave, participant_id}, timeout)
  end

  @impl true
  def init(options) do
    plan = Keyword.fetch!(options, :plan)
    host_ceiling = Keyword.get(options, :media_policy_ceiling, MediaPolicy.inherit())

    with %ResolvedCallPlan{} <- plan,
         {:ok, participant_policies} <- participant_policies(plan.participants),
         {:ok, effective} <- Effective.compose(host_ceiling, plan.media_policy, %{}) do
      {:ok,
       %{
         host_ceiling: host_ceiling,
         normal_policy: plan.media_policy,
         participant_policies: participant_policies,
         contributions: %{},
         snapshot: %Snapshot{
           revision: 0,
           present_participant_ids: MapSet.new(),
           effective: effective
         }
       }}
    else
      _invalid -> {:stop, :invalid_policy}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call({:admit, participant_id}, _from, state) do
    cond do
      Map.has_key?(state.contributions, participant_id) ->
        {:reply, {:error, :already_present}, state}

      true ->
        case Map.fetch(state.participant_policies, participant_id) do
          {:ok, policy} -> commit(Map.put(state.contributions, participant_id, policy), state)
          :error -> {:reply, {:error, :unknown_participant}, state}
        end
    end
  end

  def handle_call({:leave, participant_id}, _from, state) do
    if Map.has_key?(state.contributions, participant_id) do
      commit(Map.delete(state.contributions, participant_id), state)
    else
      {:reply, {:error, :not_present}, state}
    end
  end

  defp commit(contributions, state) do
    case Effective.compose(state.host_ceiling, state.normal_policy, contributions) do
      {:ok, effective} ->
        snapshot = %Snapshot{
          revision: state.snapshot.revision + 1,
          present_participant_ids: contributions |> Map.keys() |> MapSet.new(),
          effective: effective
        }

        {:reply, {:ok, snapshot}, %{state | contributions: contributions, snapshot: snapshot}}

      {:error, :invalid_policy} ->
        {:stop, :invalid_policy, {:error, :invalid_policy}, state}
    end
  end

  defp participant_policies(participants) when is_map(participants) do
    Enum.reduce_while(participants, {:ok, %{}}, fn
      {_definition_key, %Participant{participant_id: participant_id, while_present: policy}},
      {:ok, policies}
      when is_binary(participant_id) ->
        if Map.has_key?(policies, participant_id) or not MediaPolicy.valid?(policy) do
          {:halt, {:error, :invalid_policy}}
        else
          {:cont, {:ok, Map.put(policies, participant_id, policy)}}
        end

      {_definition_key, _participant}, _acc ->
        {:halt, {:error, :invalid_policy}}
    end)
  end

  defp participant_policies(_participants), do: {:error, :invalid_policy}

  defp via(options) do
    options
    |> Keyword.fetch!(:incarnation_id)
    |> registry_key()
    |> then(&{:via, Registry, {Vxpipe.CallEngine.RoomRegistry, &1}})
  end

  defp registry_key(incarnation_id), do: {:media_policy_authority, incarnation_id}
end
