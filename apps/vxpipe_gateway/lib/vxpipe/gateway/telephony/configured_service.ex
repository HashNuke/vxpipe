defmodule Vxpipe.Gateway.Telephony.ConfiguredService do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.IngressIdentity
  alias Vxpipe.Gateway.Telephony.Telnyx.WebhookVerifier

  @identifier ~r/\A[A-Za-z0-9][A-Za-z0-9_-]*\z/
  @maximum_identifier_bytes 128
  @maximum_provider_connection_id_bytes 128

  @derive {Inspect, only: [:identity]}
  @enforce_keys [:identity, :verifier_options]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          identity: IngressIdentity.t(),
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
         verifier_options <- [
           public_key: Keyword.fetch!(options, :public_key),
           tolerance_seconds: Keyword.fetch!(options, :webhook_tolerance_seconds)
         ],
         :ok <- WebhookVerifier.validate_configuration(verifier_options) do
      {:ok,
       %__MODULE__{
         identity: %IngressIdentity{
           service_id: service_id,
           ingress_key: ingress_key,
           scope: scope,
           provider: :telnyx,
           provider_connection_id: provider_connection_id
         },
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

  defp bounded_string(value, maximum_bytes)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= maximum_bytes,
       do: {:ok, value}

  defp bounded_string(_invalid, _maximum_bytes), do: :error
end
