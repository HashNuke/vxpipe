defmodule Vxpipe.CallEngine.OpeningAudio.AssetLoader do
  @moduledoc false

  alias Vxpipe.CallEngine.OpeningAudio.{AssetCache, Download, Settings, WaveDecoder}

  @content_types ["audio/wav", "audio/wave", "audio/x-wav"]

  @spec load(String.t(), String.t(), Settings.t()) ::
          {:ok, Vxpipe.CallEngine.OpeningAudio.Asset.t()} | {:error, :asset_unavailable}
  def load(tenant_id, url, %Settings{} = settings, options \\ [])
      when is_binary(tenant_id) and is_binary(url) do
    key =
      case Keyword.fetch(options, :profile) do
        {:ok, profile} -> AssetCache.key(tenant_id, url, profile)
        :error -> AssetCache.key(tenant_id, url)
      end

    case AssetCache.fetch(settings.cache, key, Keyword.get(options, :maximum_age_ms, :infinity)) do
      {:ok, asset} -> within_limits(asset, settings)
      :miss -> fetch_and_cache(key, url, settings, options)
    end
  catch
    :exit, _reason -> {:error, :asset_unavailable}
  end

  defp fetch_and_cache(key, url, settings, options) do
    {fetcher, fetcher_options} = settings.fetcher
    limits = [maximum_bytes: settings.maximum_bytes, timeout_ms: settings.timeout_ms]

    with {:ok, %Download{} = download} <- fetcher.fetch(url, limits, fetcher_options),
         true <- download.content_type in @content_types,
         true <- byte_size(download.body) <= settings.maximum_bytes,
         {:ok, asset} <-
           WaveDecoder.decode(download.body,
             maximum_duration_ms: settings.maximum_duration_ms,
             channels: Keyword.get(options, :channels, [1])
           ),
         :ok <- AssetCache.put(settings.cache, key, asset) do
      {:ok, asset}
    else
      _error -> {:error, :asset_unavailable}
    end
  rescue
    _exception -> {:error, :asset_unavailable}
  catch
    :exit, _reason -> {:error, :asset_unavailable}
  end

  defp within_limits(asset, settings) do
    if byte_size(asset.payload) <= settings.maximum_bytes and
         byte_size(asset.payload) * 1_000 <= settings.maximum_duration_ms * 96_000 do
      {:ok, asset}
    else
      {:error, :asset_unavailable}
    end
  end
end
