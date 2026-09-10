defmodule Vxpipe.CallEngine.OpeningAudio.AssetCache do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.OpeningAudio.Asset

  @profile "wav-pcm-s16le-48000-mono-v1"

  def start_link(options) do
    case Keyword.get(options, :name) do
      nil -> GenServer.start_link(__MODULE__, options)
      name -> GenServer.start_link(__MODULE__, options, name: name)
    end
  end

  @spec key(String.t(), String.t()) :: binary()
  def key(tenant_id, url) when is_binary(tenant_id) and is_binary(url) do
    :crypto.hash(:sha256, [tenant_id, 0, url, 0, @profile])
  end

  @spec fetch(GenServer.server(), binary()) :: :miss | {:ok, Asset.t()}
  def fetch(cache, key) when is_binary(key), do: GenServer.call(cache, {:fetch, key})

  @spec put(GenServer.server(), binary(), Asset.t()) ::
          :ok | {:error, :asset_too_large}
  def put(cache, key, %Asset{} = asset) when is_binary(key) do
    GenServer.call(cache, {:put, key, asset})
  end

  @impl true
  def init(options) do
    maximum_bytes = Keyword.get(options, :maximum_bytes)
    maximum_entries = Keyword.get(options, :maximum_entries)

    if is_integer(maximum_bytes) and maximum_bytes > 0 and is_integer(maximum_entries) and
         maximum_entries > 0 do
      {:ok,
       %{
         entries: %{},
         maximum_bytes: maximum_bytes,
         maximum_entries: maximum_entries,
         sequence: 0,
         total_bytes: 0
       }}
    else
      {:stop, :invalid_cache_configuration}
    end
  end

  @impl true
  def handle_call({:fetch, key}, _from, state) do
    case Map.fetch(state.entries, key) do
      {:ok, entry} ->
        sequence = state.sequence + 1
        entries = Map.put(state.entries, key, %{entry | touched_at: sequence})
        {:reply, {:ok, entry.asset}, %{state | entries: entries, sequence: sequence}}

      :error ->
        {:reply, :miss, state}
    end
  end

  def handle_call({:put, key, asset}, _from, state) do
    size = byte_size(asset.payload)

    if size > state.maximum_bytes do
      {:reply, {:error, :asset_too_large}, state}
    else
      state = remove_entry(state, key)
      sequence = state.sequence + 1
      entry = %{asset: asset, size: size, touched_at: sequence}

      state = %{
        state
        | entries: Map.put(state.entries, key, entry),
          sequence: sequence,
          total_bytes: state.total_bytes + size
      }

      {:reply, :ok, evict(state)}
    end
  end

  defp evict(state)
       when map_size(state.entries) <= state.maximum_entries and
              state.total_bytes <= state.maximum_bytes,
       do: state

  defp evict(state) do
    {key, _entry} = Enum.min_by(state.entries, fn {_key, entry} -> entry.touched_at end)
    state |> remove_entry(key) |> evict()
  end

  defp remove_entry(state, key) do
    case Map.pop(state.entries, key) do
      {nil, _entries} -> state
      {entry, entries} -> %{state | entries: entries, total_bytes: state.total_bytes - entry.size}
    end
  end
end
