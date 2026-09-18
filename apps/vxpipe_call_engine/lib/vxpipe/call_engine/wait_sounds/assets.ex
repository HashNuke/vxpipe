defmodule Vxpipe.CallEngine.WaitSounds.Assets do
  @moduledoc "Bounded preparation of call-level wait audio and the required transfer connection cue."

  alias Vxpipe.CallEngine.CallSpec.WaitSounds
  alias Vxpipe.CallEngine.CallSpecValidation
  alias Vxpipe.CallEngine.OpeningAudio.{AssetCache, AssetLoader, Settings, WaveDecoder}
  alias Vxpipe.CallEngine.WaitSounds.PreparedAssets

  @profile "wait-pcm-s16le-48000-average-mono-v1"
  @files %{
    phone_ring: "phone-ring.wav",
    cafe_bossa: "cafe-bossa.wav",
    connection_cue: "connection-cue.wav"
  }

  @spec prepare(String.t(), WaitSounds.t(), Settings.t(), keyword()) ::
          {:ok, PreparedAssets.t()} | {:error, Vxpipe.CallEngine.Error.t()}
  def prepare(tenant_id, %WaitSounds{} = sounds, %Settings{} = settings, options \\ []) do
    selections = Map.put(Map.from_struct(sounds), :connection_cue, :connection_cue)

    result =
      Enum.reduce_while(selections, {:ok, %{}, %{}, %{}}, fn {slot, source},
                                                             {:ok, slots, assets, sources} ->
        case resolve(tenant_id, source, sources, settings, options) do
          {:ok, nil} ->
            {:cont, {:ok, Map.put(slots, slot, nil), assets, sources}}

          {:ok, asset} ->
            digest = :crypto.hash(:sha256, [@profile, asset.payload])

            {:cont,
             {:ok, Map.put(slots, slot, digest), Map.put(assets, digest, asset),
              Map.put(sources, source, asset)}}

          {:error, _reason} ->
            {:halt, unavailable(slot)}
        end
      end)

    with {:ok, slots, assets, _sources} <- result do
      {cue, slots} = Map.pop!(slots, :connection_cue)
      {:ok, %PreparedAssets{slots: slots, assets: assets, connection_cue: cue, profile: @profile}}
    end
  end

  defp resolve(_tenant, nil, _sources, _settings, _options), do: {:ok, nil}

  defp resolve(tenant, source, sources, settings, options) do
    case Map.fetch(sources, source) do
      {:ok, asset} -> {:ok, asset}
      :error -> load(tenant, source, settings, options)
    end
  end

  defp load(tenant, url, settings, options) when is_binary(url) do
    AssetLoader.load(tenant, url, settings,
      profile: @profile,
      channels: [1, 2],
      maximum_age_ms: Keyword.get(options, :maximum_age_ms, 60_000)
    )
  end

  defp load(_tenant, source, settings, _options) when is_map_key(@files, source) do
    filename = Map.fetch!(@files, source)
    key = AssetCache.key("builtin", filename, @profile)

    case AssetCache.fetch(settings.cache, key) do
      {:ok, asset} ->
        {:ok, asset}

      :miss ->
        path = Application.app_dir(:vxpipe_call_engine, "priv/audio/wait_sounds/" <> filename)

        with {:ok, wave} <- File.read(path),
             {:ok, asset} <-
               WaveDecoder.decode(wave, maximum_duration_ms: 9_000, channels: [1, 2]),
             :ok <- AssetCache.put(settings.cache, key, asset) do
          {:ok, asset}
        end
    end
  rescue
    _exception -> {:error, :asset_unavailable}
  catch
    :exit, _reason -> {:error, :asset_unavailable}
  end

  defp unavailable(slot) do
    CallSpecValidation.invalid(
      :wait_sound_unavailable,
      "The call audio could not be prepared.",
      ["wait_sounds", Atom.to_string(slot)],
      "the selected audio asset is unavailable or unsupported"
    )
  end
end
