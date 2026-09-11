defmodule Vxpipe.Gateway.Telephony.Telnyx.ServiceProfile do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.ConfiguredServiceProfile
  alias Vxpipe.Gateway.Telephony.Telnyx.{Adapter, WebhookVerifier}

  @maximum_identifier_bytes 128
  @maximum_secret_bytes 4_096

  @spec new(keyword()) ::
          {:ok, ConfiguredServiceProfile.t()}
          | {:error, :invalid_telephony_service_configuration}
  def new(options) do
    with :ok <- no_twilio_credentials(options),
         {:ok, connection_id} <-
           bounded_string(
             Keyword.get(options, :provider_connection_id),
             @maximum_identifier_bytes
           ),
         {:ok, api_key} <- bounded_string(Keyword.get(options, :api_key), @maximum_secret_bytes),
         {:ok, adapter} <- adapter(Keyword.get(options, :adapter)),
         verifier_options <- [
           public_key: Keyword.get(options, :public_key),
           tolerance_seconds: Keyword.fetch!(options, :webhook_tolerance_seconds)
         ],
         :ok <- WebhookVerifier.validate_configuration(verifier_options) do
      {:ok,
       %ConfiguredServiceProfile{
         provider: :telnyx,
         provider_connection_id: connection_id,
         adapter: adapter,
         adapter_options: [api_key: api_key, provider_connection_id: connection_id],
         verifier_options: verifier_options
       }}
    else
      _invalid -> {:error, :invalid_telephony_service_configuration}
    end
  end

  defp no_twilio_credentials(options) do
    if is_nil(Keyword.get(options, :account_sid)) and is_nil(Keyword.get(options, :auth_token)),
      do: :ok,
      else: :error
  end

  defp adapter(nil), do: {:ok, Adapter}
  defp adapter(value) when is_atom(value), do: {:ok, value}
  defp adapter(_invalid), do: :error

  defp bounded_string(value, maximum_bytes)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= maximum_bytes,
       do: {:ok, value}

  defp bounded_string(_invalid, _maximum_bytes), do: :error
end
