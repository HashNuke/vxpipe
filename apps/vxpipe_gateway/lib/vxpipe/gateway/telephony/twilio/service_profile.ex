defmodule Vxpipe.Gateway.Telephony.Twilio.ServiceProfile do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.ConfiguredServiceProfile
  alias Vxpipe.Gateway.Telephony.Twilio.{Adapter, WebhookVerifier}

  @account_sid ~r/\AAC[0-9a-fA-F]{32}\z/
  @maximum_secret_bytes 4_096

  @spec new(keyword()) ::
          {:ok, ConfiguredServiceProfile.t()}
          | {:error, :invalid_telephony_service_configuration}
  def new(options) do
    with :ok <- no_telnyx_credentials(options),
         {:ok, account_sid} <- account_sid(Keyword.get(options, :account_sid)),
         {:ok, auth_token} <-
           bounded_string(Keyword.get(options, :auth_token), @maximum_secret_bytes),
         {:ok, adapter} <- adapter(Keyword.get(options, :adapter)),
         verifier_options <- [auth_token: auth_token],
         :ok <- WebhookVerifier.validate_configuration(verifier_options) do
      {:ok,
       %ConfiguredServiceProfile{
         provider: :twilio,
         provider_connection_id: account_sid,
         adapter: adapter,
         adapter_options: [account_sid: account_sid, auth_token: auth_token],
         verifier_options: verifier_options
       }}
    else
      _invalid -> {:error, :invalid_telephony_service_configuration}
    end
  end

  defp no_telnyx_credentials(options) do
    values =
      Enum.map([:provider_connection_id, :public_key, :api_key], &Keyword.get(options, &1))

    if Enum.all?(values, &is_nil/1), do: :ok, else: :error
  end

  defp account_sid(value) when is_binary(value) do
    if Regex.match?(@account_sid, value), do: {:ok, value}, else: :error
  end

  defp account_sid(_invalid), do: :error

  defp adapter(nil), do: {:ok, Adapter}
  defp adapter(value) when is_atom(value), do: {:ok, value}
  defp adapter(_invalid), do: :error

  defp bounded_string(value, maximum_bytes)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= maximum_bytes,
       do: {:ok, value}

  defp bounded_string(_invalid, _maximum_bytes), do: :error
end
