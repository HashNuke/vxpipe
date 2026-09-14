defmodule Vxpipe.CallEngine.RoomMixer.SubscriptionReadiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.RoomMixer.{State, Subscription, SubscriptionCatalog}

  def fetch(%State{} = state, id, token),
    do: fetch_for(state, state.subscriptions, state.policy, id, token)

  def fetch_for(state, catalog, snapshot, id, token) do
    case Map.fetch(catalog.entries, id) do
      {:ok, %{token: ^token} = entry} ->
        resource = %Resource{
          kind: kind(entry.purpose),
          scope: scope(entry),
          binding: binding(id, entry),
          instance: self(),
          generation: entry.token,
          adapter: Subscription,
          configuration:
            Resource.signature({
              state.readiness_resource.configuration,
              entry.subscriber,
              entry.mode,
              catalog.maximum_frames
            }),
          policy_interval: SubscriptionCatalog.interval(entry, snapshot)
        }

        {:ok, resource, :ready}

      _missing_or_stale ->
        {:error, :unavailable}
    end
  end

  defp binding(id, %{prepared_policy_token: token}), do: {id, :prepared_policy, token}
  defp binding(id, _entry), do: id

  defp kind(:recording), do: :recording_subscription
  defp kind(:participant), do: :audio_subscription

  defp scope(%{purpose: :recording}), do: :room
  defp scope(%{recipient_id: recipient}), do: {:participant, recipient}
end
