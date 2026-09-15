defmodule Vxpipe.Calls.ProviderAuth do
  @moduledoc "Closed, local validation of supported provider credential payloads."

  @api_key_providers ["google", "deepgram", "zenmux", "telnyx"]
  @providers @api_key_providers ++ ["twilio"]

  @spec validate(term(), term(), term()) :: :ok | {:error, :invalid_provider_auth}
  def validate(provider, "api_key", %{"api_key" => key} = payload)
      when provider in @api_key_providers and map_size(payload) == 1 and is_binary(key) do
    if byte_size(key) <= maximum_key_bytes(provider) and Regex.match?(~r/\A[\x21-\x7E]+\z/, key),
      do: :ok,
      else: {:error, :invalid_provider_auth}
  end

  def validate(
        "twilio",
        "account_sid_auth_token",
        %{"account_sid" => sid, "auth_token" => token} = payload
      )
      when map_size(payload) == 2 and is_binary(token) and byte_size(token) in 1..4_096 do
    if twilio_account_sid?(sid) and String.valid?(token),
      do: :ok,
      else: {:error, :invalid_provider_auth}
  end

  def validate(_provider, _kind, _payload), do: {:error, :invalid_provider_auth}

  @doc false
  def twilio_account_sid?(value) when is_binary(value),
    do: Regex.match?(~r/\AAC[0-9a-fA-F]{32}\z/, value)

  def twilio_account_sid?(_value), do: false

  @spec binding(term(), term(), term()) :: :ok | {:error, atom()}
  def binding(tenant_key, provider, name) when provider in @providers do
    with :ok <- tenant_key(tenant_key) do
      if is_binary(name) and byte_size(name) <= 128 and
           Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/, name),
         do: :ok,
         else: {:error, :invalid_credential_name}
    end
  end

  def binding(_tenant_key, _provider, _name), do: {:error, :invalid_provider_auth}

  @spec tenant_key(term()) :: :ok | {:error, :invalid_tenant_key}
  def tenant_key(value) do
    if is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9_-]{16}\z/, value),
      do: :ok,
      else: {:error, :invalid_tenant_key}
  end

  defp maximum_key_bytes("telnyx"), do: 4_096
  defp maximum_key_bytes(_provider), do: 8_192
end
