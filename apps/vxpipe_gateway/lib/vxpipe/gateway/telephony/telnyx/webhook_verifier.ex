defmodule Vxpipe.Gateway.Telephony.Telnyx.WebhookVerifier do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Webhook

  @default_tolerance_seconds 300
  @public_key_bytes 32
  @signature_bytes 64

  @spec verify(Webhook.t(), keyword()) ::
          :ok
          | {:error, :invalid_webhook_authentication | :invalid_webhook_verifier_configuration}
  def verify(%Webhook{} = webhook, options) when is_list(options) do
    case verifier_config(options) do
      {:ok, config} -> verify_webhook(webhook, config)
      :error -> {:error, :invalid_webhook_verifier_configuration}
    end
  end

  def verify(%Webhook{}, _invalid_options),
    do: {:error, :invalid_webhook_verifier_configuration}

  @doc false
  @spec validate_configuration(keyword()) ::
          :ok | {:error, :invalid_webhook_verifier_configuration}
  def validate_configuration(options) when is_list(options) do
    case verifier_config(options) do
      {:ok, _config} -> :ok
      :error -> {:error, :invalid_webhook_verifier_configuration}
    end
  end

  def validate_configuration(_invalid_options),
    do: {:error, :invalid_webhook_verifier_configuration}

  defp verifier_config(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             public_key: nil,
             tolerance_seconds: @default_tolerance_seconds
           ),
         {:ok, public_key} <-
           decode_sized(Keyword.fetch!(options, :public_key), @public_key_bytes),
         tolerance when is_integer(tolerance) and tolerance >= 0 <-
           Keyword.fetch!(options, :tolerance_seconds) do
      {:ok, %{public_key: public_key, tolerance_seconds: tolerance}}
    else
      _invalid -> :error
    end
  end

  defp verify_webhook(webhook, config) do
    with {:ok, timestamp} <- header(webhook.headers, "telnyx-timestamp"),
         {:ok, signed_at} <- parse_timestamp(timestamp),
         true <- fresh?(signed_at, webhook.received_at, config.tolerance_seconds),
         {:ok, encoded_signature} <-
           header(webhook.headers, "telnyx-signature-ed25519"),
         {:ok, signature} <- decode_sized(encoded_signature, @signature_bytes),
         true <-
           :crypto.verify(
             :eddsa,
             :none,
             timestamp <> "|" <> webhook.body,
             signature,
             [config.public_key, :ed25519]
           ) do
      :ok
    else
      _invalid -> {:error, :invalid_webhook_authentication}
    end
  end

  defp header(headers, name) when is_map(headers) do
    case Map.fetch(headers, name) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _missing_or_invalid -> :error
    end
  end

  defp header(_invalid, _name), do: :error

  defp parse_timestamp(value) do
    case Integer.parse(value) do
      {timestamp, ""} when timestamp >= 0 -> {:ok, timestamp}
      _invalid -> :error
    end
  end

  defp fresh?(signed_at, received_at, tolerance)
       when is_integer(received_at) and received_at >= 0 do
    abs(received_at - signed_at) <= tolerance
  end

  defp fresh?(_signed_at, _received_at, _tolerance), do: false

  defp decode_sized(value, expected_bytes) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} when byte_size(decoded) == expected_bytes -> {:ok, decoded}
      _invalid -> :error
    end
  end

  defp decode_sized(_invalid, _expected_bytes), do: :error
end
