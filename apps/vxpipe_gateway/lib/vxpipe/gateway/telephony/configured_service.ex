defmodule Vxpipe.Gateway.Telephony.ConfiguredService do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.{ConfiguredServiceProfile, IngressIdentity}

  @identifier ~r/\A[A-Za-z0-9][A-Za-z0-9_-]*\z/
  @maximum_identifier_bytes 128
  @maximum_public_url_bytes 2_048
  @phone_number ~r/\A\+[1-9][0-9]{1,14}\z/

  @derive {Inspect, only: [:identity]}
  @enforce_keys [
    :identity,
    :adapter,
    :adapter_options,
    :answering_machine_detection,
    :media_token_ttl_ms,
    :outbound_number,
    :public_base_url,
    :verifier_options
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          identity: IngressIdentity.t(),
          adapter: module(),
          adapter_options: keyword(),
          answering_machine_detection: :disabled | :detect,
          media_token_ttl_ms: pos_integer(),
          outbound_number: nil | String.t(),
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
             account_sid: nil,
             auth_token: nil,
             outbound_number: nil,
             public_base_url: nil,
             adapter: nil,
             answering_machine_detection: :disabled,
             media_token_ttl_ms: 60_000,
             webhook_tolerance_seconds: 300
           ),
         {:ok, service_id} <- identifier(Keyword.fetch!(options, :id)),
         {:ok, ingress_key} <- identifier(Keyword.fetch!(options, :ingress_key)),
         {:ok, scope} <- scope(Keyword.fetch!(options, :scope)),
         {:ok, profile} <- ConfiguredServiceProfile.new(options),
         {:ok, outbound_number} <-
           optional_phone_number(Keyword.fetch!(options, :outbound_number)),
         {:ok, public_base_url} <- public_base_url(Keyword.fetch!(options, :public_base_url)),
         {:ok, answering_machine_detection} <-
           answering_machine_detection(Keyword.fetch!(options, :answering_machine_detection)),
         {:ok, media_token_ttl_ms} <-
           positive_integer(Keyword.fetch!(options, :media_token_ttl_ms)) do
      {:ok,
       %__MODULE__{
         adapter: profile.adapter,
         adapter_options: profile.adapter_options,
         answering_machine_detection: answering_machine_detection,
         identity: %IngressIdentity{
           service_id: service_id,
           ingress_key: ingress_key,
           scope: scope,
           provider: profile.provider,
           provider_connection_id: profile.provider_connection_id
         },
         media_token_ttl_ms: media_token_ttl_ms,
         outbound_number: outbound_number,
         public_base_url: public_base_url,
         verifier_options: profile.verifier_options
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

  defp answering_machine_detection(value) when value in [:disabled, :detect], do: {:ok, value}
  defp answering_machine_detection(_invalid), do: :error

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_invalid), do: :error

  defp optional_phone_number(nil), do: {:ok, nil}

  defp optional_phone_number(value) when is_binary(value) do
    if Regex.match?(@phone_number, value), do: {:ok, value}, else: :error
  end

  defp optional_phone_number(_invalid), do: :error

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
