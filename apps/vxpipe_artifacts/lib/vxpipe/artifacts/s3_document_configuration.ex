defmodule Vxpipe.Artifacts.S3DocumentConfiguration do
  @moduledoc "Builds validated S3-compatible options for immutable document storage."

  @spec build(keyword()) :: {:ok, keyword()} | {:error, atom()}
  def build(settings) when is_list(settings) do
    with {:ok, bucket} <- bucket(settings),
         {:ok, region_options} <- region_options(settings),
         {:ok, endpoint_options} <- endpoint_options(settings) do
      {:ok,
       [
         bucket: bucket,
         client_options: [request_options: region_options ++ endpoint_options]
       ]}
    end
  end

  def build(_settings), do: {:error, :invalid_document_configuration}

  defp bucket(settings) do
    case Keyword.get(settings, :bucket) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, :document_bucket_required}
    end
  end

  defp region_options(settings) do
    case Keyword.get(settings, :region) do
      value when value in [nil, ""] -> {:ok, []}
      value when is_binary(value) -> {:ok, [region: value]}
      _invalid -> {:error, :invalid_document_region}
    end
  end

  defp endpoint_options(settings) do
    case Keyword.get(settings, :endpoint) do
      value when value in [nil, ""] -> {:ok, []}
      value when is_binary(value) -> parse_endpoint(value)
      _invalid -> {:error, :invalid_document_endpoint}
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
        {:error, :invalid_document_endpoint}
    end
  end
end
