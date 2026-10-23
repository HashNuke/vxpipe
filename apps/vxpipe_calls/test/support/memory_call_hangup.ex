defmodule Vxpipe.Calls.TestMemoryCallHangup do
  @moduledoc false

  def request(agent, tenant, id, now) do
    Agent.get_and_update(agent, fn state ->
      case Map.fetch(state.calls, {tenant, id}) do
        {:ok, call} ->
          changed = cancel(call, state.admissions, now)
          {{:ok, changed}, %{state | calls: Map.put(state.calls, {tenant, id}, changed)}}

        :error ->
          {{:error, :not_found}, state}
      end
    end)
  end

  defp cancel(%{state: :ended} = call, _admissions, _now), do: call
  defp cancel(%{hangup_requested_at: %DateTime{}} = call, _admissions, _now), do: call

  defp cancel(call, admissions, now) do
    claimed? = Enum.any?(admissions, fn {{id, _, _}, _} -> id == call.id end)

    if call.state == :prepared and is_nil(call.incarnation_id) and is_nil(call.started_at) and
         not claimed?,
       do: %{
         call
         | state: :ended,
           ended_at: now,
           terminal_reason: :api_hangup,
           hangup_requested_at: now
       },
       else: %{call | hangup_requested_at: now}
  end
end
