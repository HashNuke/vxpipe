defmodule Vxpipe.CallEngine.RoomMixer.PreparedSubscriptions do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomMixer.{SubscriptionCatalog, SubscriptionReadiness}

  def new(state),
    do: %{catalog: SubscriptionCatalog.new(state.subscriptions.maximum_frames), selected: %{}}

  def stage(state, prepared, snapshot, requested) do
    ids = Enum.map(requested, &Keyword.get(&1, :id))
    retained = select(prepared.catalog, ids)
    removed = select(prepared.catalog, Map.keys(prepared.catalog.entries) -- ids)
    original = merge(state.subscriptions, retained)

    result =
      Enum.reduce_while(requested, {:ok, original, %{}}, fn options, {:ok, catalog, selected} ->
        case SubscriptionCatalog.prepare(
               catalog,
               options,
               state.identity,
               snapshot,
               self(),
               state.source_sequences
             ) do
          {:ok, handle, catalog} ->
            selected = Map.put(selected, handle.id, %{handle: handle, options: options})

            if map_size(selected) <= 255,
              do: {:cont, {:ok, catalog, selected}},
              else: {:halt, {:error, :too_many_resources, catalog}}

          {:error, reason} ->
            {:halt, {:error, reason, catalog}}
        end
      end)

    case result do
      {:ok, catalog, selected} ->
        cleanup(%{catalog: removed})

        pending = %{
          catalog
          | entries: Map.drop(catalog.entries, Map.keys(state.subscriptions.entries)),
            monitors: Map.drop(catalog.monitors, Map.keys(state.subscriptions.monitors))
        }

        {:ok, %{catalog: pending, selected: selected}}

      {:error, reason, catalog} ->
        catalog.monitors |> Map.drop(Map.keys(original.monitors)) |> demonitor()
        {:error, reason}
    end
  end

  def valid?(state, prepared, snapshot) do
    catalog = merge(state.subscriptions, prepared.catalog)

    Enum.all?(prepared.selected, fn {id, %{handle: handle}} ->
      match?(%{token: token} when token == handle.token, Map.get(catalog.entries, id))
    end) and match?({:ok, _}, stage(state, prepared, snapshot, options(prepared)))
  end

  def options(prepared),
    do: Enum.map(prepared.selected, fn {_id, selection} -> selection.options end)

  def resources(state, prepared, snapshot, lease) do
    prepared.selected
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {id, %{handle: handle}} ->
      {:ok, resource, :ready} = binding(state, prepared, snapshot, id, handle.token)

      case SubscriptionReadiness.fetch(state, id, handle.token) do
        {:ok, ^resource, :ready} -> resource
        _changed -> %{resource | binding: {id, :prepared_policy, lease}}
      end
    end)
  end

  def binding(state, prepared, snapshot, id, token),
    do:
      SubscriptionReadiness.fetch_for(
        state,
        merge(state.subscriptions, prepared.catalog),
        snapshot,
        id,
        token
      )

  def handles(prepared, resources, lease) do
    aliased =
      for %{binding: {id, :prepared_policy, ^lease}} <- resources, into: MapSet.new(), do: id

    Map.new(prepared.selected, fn {id, selection} ->
      handle =
        if MapSet.member?(aliased, id),
          do: %{selection.handle | prepared_policy_token: lease},
          else: selection.handle

      {id, handle}
    end)
  end

  def adopt(state, prepared, snapshot, lease) do
    aliased =
      for %{binding: {id, :prepared_policy, ^lease}} <-
            resources(state, prepared, snapshot, lease),
          into: MapSet.new(),
          do: id

    catalog = merge(state.subscriptions, prepared.catalog)

    entries =
      Map.new(catalog.entries, fn {id, entry} ->
        entry =
          if Map.has_key?(prepared.catalog.entries, id),
            do: Map.put(entry, :source_cutoffs, state.source_sequences),
            else: entry

        entry =
          if MapSet.member?(aliased, id),
            do: Map.put(entry, :prepared_policy_token, lease),
            else: entry

        {id, entry}
      end)

    %{catalog | entries: entries}
  end

  def cleanup(prepared) do
    demonitor(prepared.catalog.monitors)

    Enum.each(prepared.catalog.entries, fn {id, entry} ->
      send(entry.subscriber, {:vxpipe_room_subscription_cancelled, self(), id, entry.token})
    end)
  end

  def owns_monitor?(prepared, monitor),
    do: Map.has_key?(prepared.catalog.monitors, monitor)

  defp merge(current, pending),
    do: %{
      current
      | entries: Map.merge(current.entries, pending.entries),
        monitors: Map.merge(current.monitors, pending.monitors)
    }

  defp select(catalog, ids) do
    ids_set = MapSet.new(ids)

    %{
      catalog
      | entries: Map.take(catalog.entries, ids),
        monitors:
          Map.filter(catalog.monitors, fn {_monitor, id} -> MapSet.member?(ids_set, id) end)
    }
  end

  defp demonitor(monitors) do
    Enum.each(monitors, fn {monitor, _id} -> Process.demonitor(monitor, [:flush]) end)
    :ok
  end
end
