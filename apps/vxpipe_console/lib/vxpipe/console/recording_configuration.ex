defmodule Vxpipe.Console.RecordingConfiguration do
  @moduledoc false

  @maximum_pull_frames 16
  @maximum_egress_frames 100
  @maximum_pending_chunks 100
  @drain_timeout_ms 30_000

  @spec build(keyword()) :: {:ok, keyword()} | {:error, atom()}
  def build(settings) when is_list(settings) do
    with {:ok, enabled?} <- enabled(settings) do
      if enabled?, do: enabled_configuration(settings), else: {:ok, [enabled: false]}
    end
  end

  def build(_settings), do: {:error, :invalid_recording_configuration}

  defp enabled(settings) do
    case Keyword.get(settings, :enabled) do
      value when value in [nil, false, "", "0", "false"] -> {:ok, false}
      value when value in [true, "1", "true"] -> {:ok, true}
      _invalid -> {:error, :invalid_recording_enabled}
    end
  end

  defp enabled_configuration(settings) do
    with :ok <- persistence_enabled(settings),
         {:ok, bucket} <- nonempty(settings, :bucket, :recording_bucket_required),
         {:ok, region_options} <- region_options(settings),
         {:ok, endpoint_options} <- endpoint_options(settings) do
      request_options = region_options ++ endpoint_options

      {:ok,
       [
         enabled: true,
         targets: [:full_mix, :individual_tracks],
         maximum_egress_frames: @maximum_egress_frames,
         maximum_pull_frames: @maximum_pull_frames,
         writer:
           {Vxpipe.Artifacts.RecordingWriter,
            [
              object_store: Vxpipe.Artifacts.S3ObjectStore,
              object_store_options: [
                bucket: bucket,
                client_options: [request_options: request_options]
              ],
              maximum_pending_chunks: @maximum_pending_chunks,
              drain_timeout_ms: @drain_timeout_ms,
              metadata: [
                writer: {Vxpipe.Persistence.EctoStorage, []},
                maximum_attempts: 5,
                retry_delay_ms: 250,
                write_timeout_ms: 5_000
              ]
            ]}
       ]}
    end
  end

  defp persistence_enabled(settings) do
    if Keyword.get(settings, :persistence_enabled, false),
      do: :ok,
      else: {:error, :recording_persistence_required}
  end

  defp region_options(settings) do
    case Keyword.get(settings, :region) do
      value when value in [nil, ""] -> {:ok, []}
      value when is_binary(value) -> {:ok, [region: value]}
      _invalid -> {:error, :invalid_recording_region}
    end
  end

  defp endpoint_options(settings) do
    case Keyword.get(settings, :endpoint) do
      value when value in [nil, ""] ->
        {:ok, []}

      value when is_binary(value) ->
        parse_endpoint(value)

      _invalid ->
        {:error, :invalid_recording_endpoint}
    end
  end

  defp parse_endpoint(value) do
    case URI.parse(value) do
      %URI{
        scheme: scheme,
        host: host,
        port: port,
        path: path,
        query: nil,
        fragment: nil,
        userinfo: nil
      }
      when scheme in ["http", "https"] and is_binary(host) and host != "" and
             is_integer(port) and path in [nil, "", "/"] ->
        {:ok,
         [
           scheme: scheme <> "://",
           host: host,
           port: port,
           virtual_host: false
         ]}

      _invalid ->
        {:error, :invalid_recording_endpoint}
    end
  end

  defp nonempty(settings, key, error) do
    case Keyword.get(settings, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, error}
    end
  end
end
