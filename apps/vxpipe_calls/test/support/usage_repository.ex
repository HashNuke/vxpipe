defmodule Vxpipe.Calls.TestUsageRepository do
  use Agent

  @behaviour Vxpipe.Calls.UsageRepository

  alias Vxpipe.CallEngine.Usage.{Observation, Settlement}

  def start_link(options) do
    Agent.start_link(fn ->
      %{
        tenant_key: Keyword.fetch!(options, :tenant_key),
        call_id: Keyword.fetch!(options, :call_id),
        observations: Keyword.get(options, :observations, []),
        available?: true,
        store_error: nil
      }
    end)
  end

  def repository(agent), do: {__MODULE__, agent}
  def observations(agent), do: Agent.get(agent, & &1.observations)

  def purge(agent), do: Agent.update(agent, &%{&1 | available?: false, observations: []})
  def reject_stores(agent, reason), do: Agent.update(agent, &%{&1 | store_error: reason})

  @impl true
  def store_usage_observation(agent, %Observation{} = observation) do
    Agent.get_and_update(agent, fn state -> store(state, observation) end)
  end

  @impl true
  def fetch_usage_observations(agent, tenant_key, call_id) do
    Agent.get(agent, fn state ->
      if available?(state, tenant_key, call_id),
        do: {:ok, state.observations},
        else: {:error, :call_not_found}
    end)
  end

  @impl true
  def fetch_usage_amounts(agent, tenant_key, call_id) do
    Agent.get(agent, fn state ->
      if available?(state, tenant_key, call_id) do
        case state.observations do
          [] -> {:ok, []}
          observations -> Settlement.effective_amounts(observations)
        end
      else
        {:error, :call_not_found}
      end
    end)
  end

  defp store(%{store_error: reason} = state, _observation) when not is_nil(reason),
    do: {{:error, reason}, state}

  defp store(state, observation) do
    if available?(state, observation.tenant_id, observation.call_id) do
      case Enum.find(state.observations, &(&1.id == observation.id)) do
        nil ->
          observations = state.observations ++ [observation]
          {{:ok, observation}, %{state | observations: observations}}

        ^observation ->
          {{:ok, observation}, state}

        _different ->
          {{:error, :usage_observation_conflict}, state}
      end
    else
      {{:error, :call_not_found}, state}
    end
  end

  defp available?(state, tenant_key, call_id) do
    state.available? and state.tenant_key == tenant_key and state.call_id == call_id
  end
end
