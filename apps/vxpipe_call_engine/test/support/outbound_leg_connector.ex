defmodule Vxpipe.CallEngine.TestOutboundLegConnector do
  @behaviour Vxpipe.CallEngine.Telephony.OutboundLegConnector

  alias Vxpipe.CallEngine.Telephony.OutboundLegRequest

  @impl true
  def connect(context, %OutboundLegRequest{} = request, timeout) do
    observer = observer(context)
    send(observer, {:test_outbound_leg_connect, self(), request, timeout})

    if is_map(context) and Map.get(context, :block?, false) do
      receive do
        :release_test_dial -> :ok
      end
    end

    cond do
      is_map(context) and Map.get(context, :result) == :failed ->
        {:error, :test_submission_failed}

      is_map(context) and Map.get(context, :submission_status) == :unknown ->
        {:ok, request.participant_id, :unknown}

      true ->
        {:ok, request.participant_id}
    end
  end

  @impl true
  def disconnect(context, reference) do
    observer = observer(context)
    send(observer, {:test_outbound_leg_disconnect, self(), reference})
    :ok
  end

  @impl true
  def owner(%{owner: owner}, _reference) when is_pid(owner), do: {:ok, owner}
  def owner(observer, _reference) when is_pid(observer), do: {:ok, observer}

  defp observer(%{observer: observer}) when is_pid(observer), do: observer
  defp observer(observer) when is_pid(observer), do: observer
end
