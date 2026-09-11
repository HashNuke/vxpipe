defmodule Vxpipe.Gateway.Telephony.ConfiguredService do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.IngressIdentity
  alias Vxpipe.Gateway.Telephony.Telnyx.{Adapter, WebhookVerifier}

  @identifier ~r/\A[A-Za-z0-9][A-Za-z0-9_-]*\z/
  @maximum_identifier_bytes 128
  @maximum_provider_connection_id_bytes 128
  @maximum_api_key_bytes 4_096
  @maximum_public_url_bytes 2_048

  @derive {Inspect, only: [:identity]}
  @enforce_keys [
    :identity,
    :adapter,
    :adapter_options,
    :media_token_ttl_ms,
    :public_base_url,
    :verifier_options
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          identity: IngressIdentity.t(),
          adapter: module(),
          adapter_options: keyword(),
          media_token_ttl_ms: pos_integer(),
          public_base_url: String.t(),
          verifier_options: keyword()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_telephony_service_configuration}
  def new(options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             id: nil,
             ingress_key: nil,
             scope: nil,
             provider: nil,
             provider_connection_id: nil,
             public_key: nil,
             api_key: nil,
             public_base_url: nil,
             adapter: Adapter,
             media_token_ttl_ms: 60_000,
             webhook_tolerance_seconds: 300
           ),
         {:ok, service_id} <- identifier(Keyword.fetch!(options, :id)),
         {:ok, ingress_key} <- identifier(Keyword.fetch!(options, :ingress_key)),
         {:ok, scope} <- scope(Keyword.fetch!(options, :scope)),
         :ok <- provider(Keyword.fetch!(options, :provider)),
         {:ok, provider_connection_id} <-
           bounded_string(
             Keyword.fetch!(options, :provider_connection_id),
             @maximum_provider_connection_id_bytes
           ),
         {:ok, api_key} <-
           bounded_string(Keyword.fetch!(options, :api_key), @maximum_api_key_bytes),
         {:ok, public_base_url} <- public_base_url(Keyword.fetch!(options, :public_base_url)),
         {:ok, adapter} <- adapter(Keyword.fetch!(options, :adapter)),
         {:ok, media_token_ttl_ms} <-
           positive_integer(Keyword.fetch!(options, :media_token_ttl_ms)),
         verifier_options <- [
           public_key: Keyword.fetch!(options, :public_key),
           tolerance_seconds: Keyword.fetch!(options, :webhook_tolerance_seconds)
         ],
         :ok <- WebhookVerifier.validate_configuration(verifier_options) do
      {:ok,
       %__MODULE__{
         adapter: adapter,
         adapter_options: [
           api_key: api_key,
           provider_connection_id: provider_connection_id
         ],
         identity: %IngressIdentity{
           service_id: service_id,
           ingress_key: ingress_key,
           scope: scope,
           provider: :telnyx,
           provider_connection_id: provider_connection_id
         },
         media_token_ttl_ms: media_token_ttl_ms,
         public_base_url: public_base_url,
         verifier_options: verifier_options
       }}
    else
      _invalid -> {:error, :invalid_telephony_service_configuration}
    end
  end

  def new(_invalid), do: {:error, :invalid_telephony_service_configuration}

  defp identifier(value) do
    with {:ok, value} <- bounded_string(value, @maximum_identifier_bytes),
         true <- Regex.match?(@identifier, value) do
      {:ok, value}
    else
      _invalid -> :error
    end
  end

  defp scope(:application), do: {:ok, :application}

  defp scope({:tenant, tenant_key}) do
    with {:ok, tenant_key} <- identifier(tenant_key) do
      {:ok, {:tenant, tenant_key}}
    end
  end

  defp scope(_invalid), do: :error

  defp provider(:telnyx), do: :ok
  defp provider(_unsupported), do: :error

  defp adapter(value) when is_atom(value), do: {:ok, value}
  defp adapter(_invalid), do: :error

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_invalid), do: :error

  defp public_base_url(value) do
    with {:ok, value} <- bounded_string(value, @maximum_public_url_bytes),
         %URI{
           scheme: "https",
           host: host,
           userinfo: nil,
           query: nil,
           fragment: nil
         } = uri <- URI.parse(value),
         true <- is_binary(host) and host != "" do
      {:ok, uri |> Map.put(:path, normalize_path(uri.path)) |> URI.to_string()}
    else
      _invalid -> :error
    end
  end

  defp normalize_path(path) when path in [nil, "", "/"], do: ""
  defp normalize_path(path), do: String.trim_trailing(path, "/")

  defp bounded_string(value, maximum_bytes)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= maximum_bytes,
       do: {:ok, value}

  defp bounded_string(_invalid, _maximum_bytes), do: :error
end
