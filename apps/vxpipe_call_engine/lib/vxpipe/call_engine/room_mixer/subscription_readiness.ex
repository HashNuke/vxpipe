defmodule Vxpipe.CallEngine.RoomMixer.SubscriptionReadiness do
  @moduledoc false

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.RoomMixer.{State, Subscription, SubscriptionCatalog}

  def fetch(%State{} = state, id, token) do
    case Map.fetch(state.subscriptions.entries, id) do
      {:ok, %{token: ^token} = entry} ->
        resource = %Resource{
          kind: kind(entry.purpose),
          scope: scope(entry),
          binding: id,
          instance: self(),
          generation: entry.token,
          adapter: Subscription,
          configuration:
            Resource.signature({
              state.readiness_resource.configuration,
              entry.subscriber,
              entry.mode,
              state.subscriptions.maximum_frames
            }),
          policy_interval: SubscriptionCatalog.interval(entry, state.policy)
        }

        {:ok, resource, :ready}

      _missing_or_stale ->
        {:error, :unavailable}
    end
  end

  defp kind(:recording), do: :recording_subscription
  defp kind(:participant), do: :audio_subscription

  defp scope(%{purpose: :recording}), do: :room
  defp scope(%{recipient_id: recipient}), do: {:participant, recipient}
end
