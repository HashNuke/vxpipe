defmodule Vxpipe.Gateway.Telephony.Twilio.WebhookVerifier do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Webhook
  alias Vxpipe.Gateway.Telephony.Twilio.Form

  @maximum_secret_bytes 4_096

  @spec validate_configuration(keyword()) ::
          :ok | {:error, :invalid_twilio_webhook_verifier_configuration}
  def validate_configuration(options) when is_list(options) do
    case Keyword.get(options, :auth_token) do
      value
      when is_binary(value) and byte_size(value) > 0 and
             byte_size(value) <= @maximum_secret_bytes ->
        :ok

      _invalid ->
        {:error, :invalid_twilio_webhook_verifier_configuration}
    end
  end

  def validate_configuration(_invalid),
    do: {:error, :invalid_twilio_webhook_verifier_configuration}

  @spec verify(Webhook.t(), keyword()) ::
          :ok
          | {:error,
             :invalid_twilio_webhook_authentication
             | :invalid_twilio_webhook_verifier_configuration}
  def verify(%Webhook{} = webhook, options) do
    with :ok <- validate_configuration(options),
         {:ok, signature} <- signature(webhook.headers),
         {:ok, url} <- present_url(webhook.url),
         {:ok, parameters} <- Form.decode(webhook.body),
         expected <- expected_signature(url, parameters, Keyword.fetch!(options, :auth_token)),
         true <- secure_compare(expected, signature) do
      :ok
    else
      {:error, :invalid_twilio_webhook_verifier_configuration} = error -> error
      _invalid -> {:error, :invalid_twilio_webhook_authentication}
    end
  end

  defp signature(%{"x-twilio-signature" => value}) when is_binary(value) and value != "",
    do: {:ok, value}

  defp signature(_missing), do: :error

  defp present_url(value) when is_binary(value) and value != "", do: {:ok, value}
  defp present_url(_missing), do: :error

  defp expected_signature(url, parameters, auth_token) do
    signed =
      parameters
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.reduce(url, fn {key, value}, input -> input <> key <> value end)

    :crypto.mac(:hmac, :sha, auth_token, signed)
    |> Base.encode64()
  end

  defp secure_compare(expected, actual) when byte_size(expected) == byte_size(actual),
    do: Plug.Crypto.secure_compare(expected, actual)

  defp secure_compare(_expected, _actual), do: false
end
