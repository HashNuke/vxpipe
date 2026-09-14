defmodule Vxpipe.CallEngine.RoomMixer.PreparedRecordings do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomMixer.{Subscription, SubscriptionReadiness}

  def capture(state, snapshot, lease) do
    for {id, %{purpose: :recording} = entry} <- state.subscriptions.entries, into: %{} do
      {:ok, desired, :ready} =
        SubscriptionReadiness.fetch_for(state, state.subscriptions, snapshot, id, entry.token)

      {:ok, current, :ready} = SubscriptionReadiness.fetch(state, id, entry.token)

      resource =
        if desired == current,
          do: desired,
          else: %{desired | binding: {id, :prepared_policy, lease}}

      prepared_token =
        case resource.binding do
          {^id, :prepared_policy, token} -> token
          _current -> nil
        end

      handle =
        struct!(
          Subscription,
          Map.merge(state.identity, %{
            id: id,
            mixer: self(),
            token: entry.token,
            prepared_policy_token: prepared_token,
            recipient_participant_id: nil,
            mode: entry.mode,
            purpose: :recording
          })
        )

      {id, %{resource: resource, handle: handle}}
    end
  end

  def valid?(state, recordings, snapshot) do
    Enum.all?(recordings, fn {id, %{resource: expected, handle: handle}} ->
      case SubscriptionReadiness.fetch_for(state, state.subscriptions, snapshot, id, handle.token) do
        {:ok, actual, :ready} -> %{actual | binding: expected.binding} == expected
        _unavailable -> false
      end
    end)
  end

  def adopt(catalog, recordings, lease) do
    entries =
      Enum.reduce(recordings, catalog.entries, fn
        {id, %{resource: %{binding: {_id, :prepared_policy, ^lease}}}}, entries ->
          Map.update!(entries, id, &Map.put(&1, :prepared_policy_token, lease))

        _retained, entries ->
          entries
      end)

    %{catalog | entries: entries}
  end

  def resources(recordings),
    do: recordings |> Enum.sort() |> Enum.map(fn {_id, binding} -> binding.resource end)

  def handles(recordings), do: Map.new(recordings, fn {id, binding} -> {id, binding.handle} end)
end
